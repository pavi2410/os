const hal = @import("../hal.zig");
const virtual = @import("../mm/virtual.zig");
const block = @import("block.zig");
const virtio_pci = @import("virtio_pci.zig");
const virtio_queue = @import("virtio_queue.zig");

pub const sector_size = 512;

pub const BlkError = virtio_pci.VirtioError || error{
    NotReady,
    IoError,
    Timeout,
};

const VIRTIO_F_VERSION_1: u64 = 1 << 32;

const VIRTIO_BLK_T_IN: u32 = 0;
const VIRTIO_BLK_T_OUT: u32 = 1;

const BlkReqHeader = extern struct {
    type: u32,
    reserved: u32,
    sector: u64,
};

var device: virtio_pci.Device = undefined;
var ready = false;
var capacity_sectors: u64 = 0;

var queue: virtio_queue.Queue = .{};
var req_header: *align(4096) BlkReqHeader = undefined;
var req_status: *align(4096) u8 = undefined;

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
    block.registerDefault(blockDevice());
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

fn blockDevice() block.Device {
    return .{
        .name = "virtio-blk",
        .sector_size = sector_size,
        .capacity_sectors = capacity_sectors,
        .is_ready = blockIsReady,
        .read_sectors = blockReadSectors,
        .write_sectors = blockWriteSectors,
    };
}

fn blockIsReady(ctx: ?*anyopaque) bool {
    _ = ctx;
    return isReady();
}

fn blockReadSectors(ctx: ?*anyopaque, lba: u64, buf: []u8) block.Error!void {
    _ = ctx;
    readSectors(lba, buf) catch |err| return blockError(err);
}

fn blockWriteSectors(ctx: ?*anyopaque, lba: u64, buf: []const u8) block.Error!void {
    _ = ctx;
    writeSectors(lba, buf) catch |err| return blockError(err);
}

fn blockError(err: BlkError) block.Error {
    return switch (err) {
        BlkError.NotReady => block.Error.NotReady,
        BlkError.Timeout => block.Error.Timeout,
        else => block.Error.IoError,
    };
}

pub fn logStatus() void {
    hal.console.writeString("\r\n--- VirtIO Block ---\r\n");
    if (!ready) {
        hal.console.writeString("Not available\r\n");
        return;
    }
    hal.console.printf("Queue size: {d}\r\n", .{queue.size});
    hal.console.printf("Capacity: {d} sectors ({d} MiB)\r\n", .{
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
        hal.console.writeString("virtio-blk read test failed\r\n");
        return;
    };

    if (sector[510] == 0x55 and sector[511] == 0xAA) {
        hal.console.writeString("virtio-blk sector 0 boot signature ok\r\n");
    } else {
        hal.console.writeString("virtio-blk sector 0 read ok (no MBR signature)\r\n");
    }
}

const TransferDir = enum { in, out };

fn setupQueue() BlkError!void {
    try queue.init(&device, 0);
    const header_virt = virtual.allocPages(1) catch return BlkError.QueueSetupFailed;
    const status_virt = virtual.allocPages(1) catch return BlkError.QueueSetupFailed;

    req_header = @ptrFromInt(header_virt);
    req_status = @ptrFromInt(status_virt);
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

    const segments = [_]virtio_queue.Segment{
        .{ .phys = header_phys, .len = @sizeOf(BlkReqHeader) },
        .{ .phys = data_phys, .len = sector_size, .writable = dir == .in },
        .{ .phys = status_phys, .len = 1, .writable = true },
    };
    queue.writeChain(0, &segments);

    queue.submit(0);
    queue.notify(&device);
    _ = try queue.waitUsed(&device);

    if (req_status.* != 0) return BlkError.IoError;
}
