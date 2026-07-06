const serial = @import("../arch/x86_64/serial.zig");
const virtual = @import("../mm/virtual.zig");
const ethernet = @import("../net/ethernet.zig");
const net_device = @import("net_device.zig");
const virtio_pci = @import("virtio_pci.zig");
const virtio_queue = @import("virtio_queue.zig");

pub const NetError = virtio_pci.VirtioError || error{
    NotReady,
    IoError,
    Timeout,
    BufferTooSmall,
    NoPacket,
};

pub const max_frame_size = ethernet.max_frame_len;

const VIRTIO_F_VERSION_1: u64 = 1 << 32;

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

const rx_slots = 8;
const rx_descs_per_slot = 2;

const RxSlot = struct {
    page: *align(4096) [4096]u8,
};

var device: virtio_pci.Device = undefined;
var ready = false;
var mac: ethernet.Mac = undefined;

var rx_queue: virtio_queue.Queue = .{};
var tx_queue: virtio_queue.Queue = .{};

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
    try rx_queue.init(&device, rx_queue_index);
    try tx_queue.init(&device, tx_queue_index);

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
    net_device.registerDefault(netDevice());
}

pub fn isReady() bool {
    return ready;
}

pub fn macAddress() ethernet.Mac {
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
        .flags = virtio_queue.desc_flags.next,
        .next = 1,
    };
    tx_queue.desc_table[1] = .{
        .addr = frame_phys,
        .len = @intCast(frame.len),
        .flags = 0,
        .next = 0,
    };

    tx_queue.submit(0);
    tx_queue.notify(&device);
    _ = try tx_queue.waitUsed(&device);
}

pub fn recvFrame(buf: []u8) NetError!usize {
    if (!ready) return NetError.NotReady;
    if (buf.len < max_frame_size) return NetError.BufferTooSmall;

    if (!rx_queue.hasUsed()) {
        device.ackInterrupt();
        return NetError.NoPacket;
    }

    const used = rx_queue.popUsed();
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

fn netDevice() net_device.Device {
    return .{
        .name = "virtio-net",
        .max_frame_size = max_frame_size,
        .is_ready = netIsReady,
        .mac_address = netMacAddress,
        .send_frame = netSendFrame,
        .recv_frame = netRecvFrame,
        .poll_recv = netPollRecv,
    };
}

fn netIsReady(ctx: ?*anyopaque) bool {
    _ = ctx;
    return isReady();
}

fn netMacAddress(ctx: ?*anyopaque) net_device.Mac {
    _ = ctx;
    return macAddress();
}

fn netSendFrame(ctx: ?*anyopaque, frame: []const u8) net_device.Error!void {
    _ = ctx;
    sendFrame(frame) catch |err| return netError(err);
}

fn netRecvFrame(ctx: ?*anyopaque, buf: []u8) net_device.Error!usize {
    _ = ctx;
    return recvFrame(buf) catch |err| return netError(err);
}

fn netPollRecv(ctx: ?*anyopaque, buf: []u8, max_spins: usize) net_device.Error!usize {
    _ = ctx;
    return pollRecv(buf, max_spins) catch |err| return netError(err);
}

fn netError(err: NetError) net_device.Error {
    return switch (err) {
        NetError.NotReady => net_device.Error.NotReady,
        NetError.Timeout => net_device.Error.Timeout,
        NetError.BufferTooSmall => net_device.Error.BufferTooSmall,
        NetError.NoPacket => net_device.Error.NoPacket,
        else => net_device.Error.IoError,
    };
}

pub fn logStatus() void {
    serial.writeString("\r\n--- VirtIO Net ---\r\n");
    if (!ready) {
        serial.writeString("Not available\r\n");
        return;
    }
    var mac_buf: [ethernet.format_len]u8 = undefined;
    if (ethernet.format(mac, &mac_buf)) |s| {
        serial.printf("MAC: {s}\r\n", .{s});
    }
    serial.printf("RX slots: {d}, TX queue: {d}\r\n", .{ rx_slots, tx_queue.size });
}

fn setupRxSlots() NetError!void {
    var slot: usize = 0;
    while (slot < rx_slots) : (slot += 1) {
        const page_virt = virtual.allocPages(1) catch return NetError.QueueSetupFailed;
        rx_slots_storage[slot] = .{ .page = @ptrFromInt(page_virt) };
        try queueRxSlot(slot);
    }
    rx_queue.notify(&device);
}

fn queueRxSlot(slot: usize) NetError!void {
    const page_virt = @intFromPtr(rx_slots_storage[slot].page);
    const header_phys = virtio_pci.physFromVirt(page_virt) orelse return NetError.IoError;
    const frame_phys = virtio_pci.physFromVirt(page_virt + @sizeOf(NetHdr)) orelse return NetError.IoError;

    const desc_base: u16 = @intCast(slot * rx_descs_per_slot);
    rx_queue.desc_table[desc_base] = .{
        .addr = header_phys,
        .len = @sizeOf(NetHdr),
        .flags = virtio_queue.desc_flags.next | virtio_queue.desc_flags.write,
        .next = desc_base + 1,
    };
    rx_queue.desc_table[desc_base + 1] = .{
        .addr = frame_phys,
        .len = max_frame_size,
        .flags = virtio_queue.desc_flags.write,
        .next = 0,
    };

    rx_queue.submit(desc_base);
}

fn resubmitRxSlot(slot: usize) NetError!void {
    try queueRxSlot(slot);
    rx_queue.notify(&device);
}
