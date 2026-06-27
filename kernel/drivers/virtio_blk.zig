const serial = @import("../arch/x86_64/serial.zig");
const virtual = @import("../mm/virtual.zig");
const virtio_pci = @import("virtio_pci.zig");

pub const sector_size = 512;

pub const BlkError = virtio_pci.VirtioError || error{
    NotReady,
    IoError,
    Timeout,
};

const VIRTIO_F_VERSION_1: u64 = 1 << 32;

const VIRTIO_BLK_T_IN: u32 = 0;
const VIRTIO_BLK_T_OUT: u32 = 1;

const VIRTQ_DESC_F_NEXT: u16 = 1;
const VIRTQ_DESC_F_WRITE: u16 = 2;

const Desc = extern struct {
    addr: u64,
    len: u32,
    flags: u16,
    next: u16,
};

const max_queue_size = 256;

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

const BlkReqHeader = extern struct {
    type: u32,
    reserved: u32,
    sector: u64,
};

var device: virtio_pci.Device = undefined;
var ready = false;
var capacity_sectors: u64 = 0;
var queue_size: u16 = 0;

var desc_table: *align(4096) [max_queue_size]Desc = undefined;
var avail_ring: *align(4096) AvailRing = undefined;
var used_ring: *align(4096) UsedRing = undefined;
var req_header: *align(4096) BlkReqHeader = undefined;
var req_status: *align(4096) u8 = undefined;

var desc_phys: u64 = 0;
var avail_phys: u64 = 0;
var used_phys: u64 = 0;

var avail_idx: u16 = 0;
var last_used_idx: u16 = 0;

pub fn init() BlkError!void {
    const pci_dev = virtio_pci.findBlockDevice() orelse return BlkError.NotFound;

    device = try virtio_pci.Device.init(pci_dev);
    device.reset();
    device.acknowledge();
    device.setDriver();
    try device.negotiateFeatures(VIRTIO_F_VERSION_1);
    try setupQueue();
    device.setDriverOk();

    capacity_sectors = device.readDevice64(0);
    ready = true;
}

pub fn isReady() bool {
    return ready;
}

pub fn capacity() u64 {
    return capacity_sectors;
}

pub fn readSectors(lba: u64, buf: []u8) BlkError!void {
    if (!ready) return BlkError.NotReady;
    if (buf.len == 0 or buf.len % sector_size != 0) return BlkError.IoError;
    const sector_count = buf.len / sector_size;

    var sector: usize = 0;
    while (sector < sector_count) : (sector += 1) {
        try transferOne(.in, lba + sector, buf[sector * sector_size ..][0..sector_size]);
    }
}

pub fn writeSectors(lba: u64, buf: []const u8) BlkError!void {
    if (!ready) return BlkError.NotReady;
    if (buf.len == 0 or buf.len % sector_size != 0) return BlkError.IoError;
    const sector_count = buf.len / sector_size;

    var sector: usize = 0;
    while (sector < sector_count) : (sector += 1) {
        try transferOne(.out, lba + sector, @constCast(buf[sector * sector_size ..][0..sector_size]));
    }
}

pub fn logStatus() void {
    serial.writeString("\r\n--- VirtIO Block ---\r\n");
    if (!ready) {
        serial.writeString("Not available\r\n");
        return;
    }
    serial.printf("Queue size: {d}\r\n", .{queue_size});
    serial.printf("Capacity: {d} sectors ({d} MiB)\r\n", .{
        capacity_sectors,
        (capacity_sectors * sector_size) / (1024 * 1024),
    });
}

var test_sector_page: u64 = 0;

pub fn selfTest() void {
    if (!ready) return;
    if (test_sector_page == 0) return;

    const sector = @as([*]u8, @ptrFromInt(test_sector_page))[0..sector_size];
    readSectors(0, sector) catch {
        serial.writeString("virtio-blk read test failed\r\n");
        return;
    };

    if (sector[510] == 0x55 and sector[511] == 0xAA) {
        serial.writeString("virtio-blk sector 0 boot signature ok\r\n");
    } else {
        serial.writeString("virtio-blk sector 0 read ok (no MBR signature)\r\n");
    }
}

const TransferDir = enum { in, out };

fn setupQueue() BlkError!void {
    const desc_virt = virtual.allocPages(1) catch return BlkError.QueueSetupFailed;
    const avail_virt = virtual.allocPages(1) catch return BlkError.QueueSetupFailed;
    const used_virt = virtual.allocPages(1) catch return BlkError.QueueSetupFailed;
    const header_virt = virtual.allocPages(1) catch return BlkError.QueueSetupFailed;
    const status_virt = virtual.allocPages(1) catch return BlkError.QueueSetupFailed;

    desc_table = @ptrFromInt(desc_virt);
    avail_ring = @ptrFromInt(avail_virt);
    used_ring = @ptrFromInt(used_virt);
    req_header = @ptrFromInt(header_virt);
    req_status = @ptrFromInt(status_virt);

    desc_phys = virtio_pci.physFromVirt(desc_virt) orelse return BlkError.QueueSetupFailed;
    avail_phys = virtio_pci.physFromVirt(avail_virt) orelse return BlkError.QueueSetupFailed;
    used_phys = virtio_pci.physFromVirt(used_virt) orelse return BlkError.QueueSetupFailed;

    for (&desc_table.*) |*entry| entry.* = .{ .addr = 0, .len = 0, .flags = 0, .next = 0 };
    avail_ring.* = .{ .flags = 0, .idx = 0, .ring = undefined };
    used_ring.* = .{ .flags = 0, .idx = 0, .ring = undefined };

    queue_size = try device.setupQueue(0, desc_phys, avail_phys, used_phys, max_queue_size);
    test_sector_page = virtual.allocPages(1) catch return BlkError.QueueSetupFailed;
}

fn transferOne(dir: TransferDir, lba: u64, data: []u8) BlkError!void {
    if (data.len != sector_size) return BlkError.IoError;

    req_header.* = .{
        .type = switch (dir) {
            .in => VIRTIO_BLK_T_IN,
            .out => VIRTIO_BLK_T_OUT,
        },
        .reserved = 0,
        .sector = lba,
    };
    req_status.* = 0xFF;

    const header_phys = virtio_pci.physFromVirt(@intFromPtr(req_header)) orelse return BlkError.IoError;
    const data_phys = virtio_pci.physFromVirt(@intFromPtr(data.ptr)) orelse return BlkError.IoError;
    const status_phys = virtio_pci.physFromVirt(@intFromPtr(req_status)) orelse return BlkError.IoError;

    const data_flags: u16 = if (dir == .in) VIRTQ_DESC_F_WRITE else 0;

    desc_table[0] = .{
        .addr = header_phys,
        .len = @sizeOf(BlkReqHeader),
        .flags = VIRTQ_DESC_F_NEXT,
        .next = 1,
    };
    desc_table[1] = .{
        .addr = data_phys,
        .len = sector_size,
        .flags = VIRTQ_DESC_F_NEXT | data_flags,
        .next = 2,
    };
    desc_table[2] = .{
        .addr = status_phys,
        .len = 1,
        .flags = VIRTQ_DESC_F_WRITE,
        .next = 0,
    };

    const slot = avail_idx % queue_size;
    avail_ring.ring[slot] = 0;
    avail_idx +%= 1;
    asm volatile ("" ::: .{ .memory = true });
    avail_ring.idx = avail_idx;

    device.notifyQueue(0);

    try waitUsed();

    if (req_status.* != 0) return BlkError.IoError;
}

fn waitUsed() BlkError!void {
    var spins: usize = 0;
    while (used_ring.idx == last_used_idx) {
        device.ackInterrupt();
        // VirtIO may deliver completions via IRQ; syscall entry clears IF.
        asm volatile ("sti; pause; cli" ::: .{ .memory = true });
        spins += 1;
        if (spins > 10_000_000) return BlkError.Timeout;
    }

    asm volatile ("" ::: .{ .memory = true });
    _ = used_ring.ring[last_used_idx % queue_size];
    last_used_idx +%= 1;
    device.ackInterrupt();
}
