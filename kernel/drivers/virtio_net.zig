const serial = @import("../arch/x86_64/serial.zig");
const arp = @import("../net/arp.zig");
const virtual = @import("../mm/virtual.zig");
const virtio_pci = @import("virtio_pci.zig");

pub const NetError = virtio_pci.VirtioError || error{
    NotReady,
    IoError,
    Timeout,
    BufferTooSmall,
    NoPacket,
};

pub const mac_len = 6;
pub const max_frame_size = 1518;

const VIRTIO_F_VERSION_1: u64 = 1 << 32;

const VIRTQ_DESC_F_NEXT: u16 = 1;
const VIRTQ_DESC_F_WRITE: u16 = 2;

const rx_queue_index: u16 = 0;
const tx_queue_index: u16 = 1;

const NetHdr = extern struct {
    flags: u8,
    gso_type: u8,
    hdr_len: u16,
    gso_size: u16,
    csum_start: u16,
    csum_offset: u16,
    num_buffers: u16, // present when VIRTIO_F_VERSION_1 is negotiated
};

const Desc = extern struct {
    addr: u64,
    len: u32,
    flags: u16,
    next: u16,
};

const max_queue_size = 256;
const rx_slots = 8;
const rx_descs_per_slot = 2;

const AvailRing = extern struct {
    flags: u16,
    idx: u16,
    ring: [max_queue_size]u16,
};

const UsedElem = extern struct {
    id: u32,
    len: u32,
};

const UsedRing = extern struct {
    flags: u16,
    idx: u16,
    ring: [max_queue_size]UsedElem,
};

const Queue = struct {
    desc_table: *align(4096) [max_queue_size]Desc,
    avail_ring: *align(4096) AvailRing,
    used_ring: *align(4096) UsedRing,
    desc_phys: u64,
    avail_phys: u64,
    used_phys: u64,
    size: u16,
    avail_idx: u16,
    last_used_idx: u16,
};

const RxSlot = struct {
    page: *align(4096) [4096]u8,
};

var device: virtio_pci.Device = undefined;
var ready = false;
var mac: [mac_len]u8 = undefined;

var rx_queue: Queue = undefined;
var tx_queue: Queue = undefined;

var rx_slots_storage: [rx_slots]RxSlot = undefined;
var tx_header: *align(4096) NetHdr = undefined;
var tx_frame: *align(4096) [max_frame_size]u8 = undefined;

pub fn init() NetError!void {
    const pci_dev = virtio_pci.findNetworkDevice() orelse return NetError.NotFound;

    device = try virtio_pci.Device.init(pci_dev);
    device.reset();
    device.acknowledge();
    device.setDriver();
    try device.negotiateFeatures(VIRTIO_F_VERSION_1);
    try setupQueue(&rx_queue, rx_queue_index);
    try setupQueue(&tx_queue, tx_queue_index);

    const tx_header_virt = virtual.allocPages(1) catch return NetError.QueueSetupFailed;
    const tx_frame_virt = virtual.allocPages(1) catch return NetError.QueueSetupFailed;
    tx_header = @ptrFromInt(tx_header_virt);
    tx_frame = @ptrFromInt(tx_frame_virt);

    device.setDriverOk();

    const lo = device.readDevice32(0);
    const hi = device.readDevice32(4);
    mac[0] = @truncate(lo);
    mac[1] = @truncate(lo >> 8);
    mac[2] = @truncate(lo >> 16);
    mac[3] = @truncate(lo >> 24);
    mac[4] = @truncate(hi);
    mac[5] = @truncate(hi >> 8);

    try setupRxSlots();
    ready = true;
}

pub fn isReady() bool {
    return ready;
}

pub fn macAddress() [mac_len]u8 {
    return mac;
}

pub fn sendFrame(frame: []const u8) NetError!void {
    if (!ready) return NetError.NotReady;
    if (frame.len == 0 or frame.len > max_frame_size) return NetError.IoError;

    tx_header.* = .{
        .flags = 0,
        .gso_type = 0,
        .hdr_len = 0,
        .gso_size = 0,
        .csum_start = 0,
        .csum_offset = 0,
        .num_buffers = 0,
    };
    @memcpy(tx_frame[0..frame.len], frame);

    const header_phys = virtio_pci.physFromVirt(@intFromPtr(tx_header)) orelse return NetError.IoError;
    const frame_phys = virtio_pci.physFromVirt(@intFromPtr(tx_frame)) orelse return NetError.IoError;

    tx_queue.desc_table[0] = .{
        .addr = header_phys,
        .len = @sizeOf(NetHdr),
        .flags = VIRTQ_DESC_F_NEXT,
        .next = 1,
    };
    tx_queue.desc_table[1] = .{
        .addr = frame_phys,
        .len = @intCast(frame.len),
        .flags = 0,
        .next = 0,
    };

    const slot = tx_queue.avail_idx % tx_queue.size;
    tx_queue.avail_ring.ring[slot] = 0;
    tx_queue.avail_idx +%= 1;
    asm volatile ("" ::: .{ .memory = true });
    tx_queue.avail_ring.idx = tx_queue.avail_idx;

    device.notifyQueue(tx_queue_index);
    try waitUsed(&tx_queue);
}

fn usedIdx(queue: *const Queue) u16 {
    const ptr: *const volatile u16 = @ptrCast(@alignCast(&queue.used_ring.idx));
    return ptr.*;
}

pub fn recvFrame(buf: []u8) NetError!usize {
    if (!ready) return NetError.NotReady;
    if (buf.len < max_frame_size) return NetError.BufferTooSmall;

    if (usedIdx(&rx_queue) == rx_queue.last_used_idx) {
        device.ackInterrupt();
        return NetError.NoPacket;
    }

    asm volatile ("" ::: .{ .memory = true });
    const used = rx_queue.used_ring.ring[rx_queue.last_used_idx % rx_queue.size];
    const desc_index = @as(usize, @intCast(used.id));
    if (desc_index % rx_descs_per_slot != 0) return NetError.IoError;
    const slot_index = desc_index / rx_descs_per_slot;
    if (slot_index >= rx_slots) return NetError.IoError;

    const total_len = used.len;
    const frame_off = @sizeOf(NetHdr);
    const frame_len: usize = if (total_len > frame_off) total_len - frame_off else total_len;
    if (frame_len == 0 or frame_len > max_frame_size) return NetError.IoError;

    @memcpy(buf[0..frame_len], rx_slots_storage[slot_index].page[frame_off..][0..frame_len]);
    try resubmitRxSlot(slot_index);

    rx_queue.last_used_idx +%= 1;
    device.ackInterrupt();
    return frame_len;
}

pub fn pollRecv(buf: []u8, max_spins: usize) NetError!usize {
    var spins: usize = 0;
    while (spins < max_spins) : (spins += 1) {
        const len = recvFrame(buf) catch |err| {
            switch (err) {
                NetError.NoPacket => {
                    device.ackInterrupt();
                    asm volatile ("sti; pause; cli" ::: .{ .memory = true });
                },
                else => return err,
            }
            continue;
        };
        return len;
    }
    return NetError.Timeout;
}

pub fn logStatus() void {
    serial.writeString("\r\n--- VirtIO Net ---\r\n");
    if (!ready) {
        serial.writeString("Not available\r\n");
        return;
    }
    serial.printf(
        "MAC: {x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}\r\n",
        .{ mac[0], mac[1], mac[2], mac[3], mac[4], mac[5] },
    );
    serial.printf("RX slots: {d}, TX queue: {d}\r\n", .{ rx_slots, tx_queue.size });
}

pub fn selfTest() void {
    if (!ready) return;

    const guest_ip = [_]u8{ 10, 0, 2, 15 };
    const gateway_ip = [_]u8{ 10, 0, 2, 2 };
    var frame: [max_frame_size]u8 = undefined;
    const frame_len = arp.buildRequest(&frame, mac, guest_ip, gateway_ip);
    sendFrame(frame[0..frame_len]) catch {
        serial.writeString("virtio-net TX failed\r\n");
        return;
    };
    serial.writeString("virtio-net TX ok\r\n");

    var recv_buf: [max_frame_size]u8 = undefined;
    if (pollRecv(&recv_buf, 100_000)) |len| {
        if (arp.isReply(recv_buf[0..len])) {
            serial.printf("virtio-net ARP reply ({d} bytes)\r\n", .{len});
        } else {
            serial.printf("virtio-net RX frame ({d} bytes)\r\n", .{len});
        }
    } else |_| {
        serial.writeString("virtio-net RX timeout\r\n");
    }
}

fn setupQueue(queue: *Queue, queue_index: u16) NetError!void {
    const desc_virt = virtual.allocPages(1) catch return NetError.QueueSetupFailed;
    const avail_virt = virtual.allocPages(1) catch return NetError.QueueSetupFailed;
    const used_virt = virtual.allocPages(1) catch return NetError.QueueSetupFailed;

    queue.desc_table = @ptrFromInt(desc_virt);
    queue.avail_ring = @ptrFromInt(avail_virt);
    queue.used_ring = @ptrFromInt(used_virt);

    queue.desc_phys = virtio_pci.physFromVirt(desc_virt) orelse return NetError.QueueSetupFailed;
    queue.avail_phys = virtio_pci.physFromVirt(avail_virt) orelse return NetError.QueueSetupFailed;
    queue.used_phys = virtio_pci.physFromVirt(used_virt) orelse return NetError.QueueSetupFailed;

    for (&queue.desc_table.*) |*entry| entry.* = .{ .addr = 0, .len = 0, .flags = 0, .next = 0 };
    queue.avail_ring.* = .{ .flags = 0, .idx = 0, .ring = undefined };
    queue.used_ring.* = .{ .flags = 0, .idx = 0, .ring = undefined };
    queue.avail_idx = 0;
    queue.last_used_idx = 0;

    queue.size = try device.setupQueue(queue_index, queue.desc_phys, queue.avail_phys, queue.used_phys, max_queue_size);
}

fn setupRxSlots() NetError!void {
    var slot: usize = 0;
    while (slot < rx_slots) : (slot += 1) {
        const page_virt = virtual.allocPages(1) catch return NetError.QueueSetupFailed;
        rx_slots_storage[slot] = .{ .page = @ptrFromInt(page_virt) };
        try queueRxSlot(slot);
    }
    device.notifyQueue(rx_queue_index);
}

fn queueRxSlot(slot: usize) NetError!void {
    const page_virt = @intFromPtr(rx_slots_storage[slot].page);
    const header_phys = virtio_pci.physFromVirt(page_virt) orelse return NetError.IoError;
    const frame_phys = virtio_pci.physFromVirt(page_virt + @sizeOf(NetHdr)) orelse return NetError.IoError;

    const desc_base: u16 = @intCast(slot * rx_descs_per_slot);
    rx_queue.desc_table[desc_base] = .{
        .addr = header_phys,
        .len = @sizeOf(NetHdr),
        .flags = VIRTQ_DESC_F_NEXT | VIRTQ_DESC_F_WRITE,
        .next = desc_base + 1,
    };
    rx_queue.desc_table[desc_base + 1] = .{
        .addr = frame_phys,
        .len = max_frame_size,
        .flags = VIRTQ_DESC_F_WRITE,
        .next = 0,
    };

    const ring_slot = rx_queue.avail_idx % rx_queue.size;
    rx_queue.avail_ring.ring[ring_slot] = desc_base;
    rx_queue.avail_idx +%= 1;
    asm volatile ("" ::: .{ .memory = true });
    rx_queue.avail_ring.idx = rx_queue.avail_idx;
}

fn resubmitRxSlot(slot: usize) NetError!void {
    try queueRxSlot(slot);
    device.notifyQueue(rx_queue_index);
}

fn waitUsed(queue: *Queue) NetError!void {
    var spins: usize = 0;
    while (usedIdx(queue) == queue.last_used_idx) {
        device.ackInterrupt();
        asm volatile ("sti; pause; cli" ::: .{ .memory = true });
        spins += 1;
        if (spins > 10_000_000) return NetError.Timeout;
    }

    asm volatile ("" ::: .{ .memory = true });
    _ = queue.used_ring.ring[queue.last_used_idx % queue.size];
    queue.last_used_idx +%= 1;
    device.ackInterrupt();
}
