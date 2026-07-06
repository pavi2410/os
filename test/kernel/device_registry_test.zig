const std = @import("std");
const block = @import("block");
const net_device = @import("net_device");

var block_read_lba: u64 = 0;
var block_write_lba: u64 = 0;

fn blockReady(ctx: ?*anyopaque) bool {
    _ = ctx;
    return true;
}

fn blockRead(ctx: ?*anyopaque, lba: u64, buf: []u8) block.Error!void {
    _ = ctx;
    block_read_lba = lba;
    if (buf.len > 0) buf[0] = 0xAA;
}

fn blockWrite(ctx: ?*anyopaque, lba: u64, buf: []const u8) block.Error!void {
    _ = ctx;
    _ = buf;
    block_write_lba = lba;
}

fn fakeBlock() block.Device {
    return .{
        .name = "fake-block",
        .sector_size = 512,
        .capacity_sectors = 128,
        .is_ready = blockReady,
        .read_sectors = blockRead,
        .write_sectors = blockWrite,
    };
}

test "block registry exposes the default device" {
    block.clearDefaultForTest();
    try std.testing.expect(block.default() == null);

    block.registerDefault(fakeBlock());
    const dev = block.default().?;
    try std.testing.expect(dev.isReady());
    try std.testing.expectEqual(@as(usize, 512), dev.sectorSize());
    try std.testing.expectEqual(@as(u64, 128), dev.capacity());

    var buf: [512]u8 = undefined;
    try dev.readSectors(7, &buf);
    try std.testing.expectEqual(@as(u64, 7), block_read_lba);
    try std.testing.expectEqual(@as(u8, 0xAA), buf[0]);

    try dev.writeSectors(9, &buf);
    try std.testing.expectEqual(@as(u64, 9), block_write_lba);
}

fn netReady(ctx: ?*anyopaque) bool {
    _ = ctx;
    return true;
}

fn netMac(ctx: ?*anyopaque) net_device.Mac {
    _ = ctx;
    return .{ 0x52, 0x54, 0, 0x12, 0x34, 0x56 };
}

fn netSend(ctx: ?*anyopaque, frame: []const u8) net_device.Error!void {
    _ = ctx;
    if (frame.len == 0) return net_device.Error.IoError;
}

fn netRecv(ctx: ?*anyopaque, buf: []u8) net_device.Error!usize {
    _ = ctx;
    if (buf.len < 2) return net_device.Error.BufferTooSmall;
    buf[0] = 1;
    buf[1] = 2;
    return 2;
}

fn netPoll(ctx: ?*anyopaque, buf: []u8, max_spins: usize) net_device.Error!usize {
    _ = max_spins;
    return netRecv(ctx, buf);
}

fn fakeNet() net_device.Device {
    return .{
        .name = "fake-net",
        .max_frame_size = 1514,
        .is_ready = netReady,
        .mac_address = netMac,
        .send_frame = netSend,
        .recv_frame = netRecv,
        .poll_recv = netPoll,
    };
}

test "net registry exposes the default device" {
    net_device.clearDefaultForTest();
    try std.testing.expect(net_device.default() == null);

    net_device.registerDefault(fakeNet());
    const dev = net_device.default().?;
    try std.testing.expect(dev.isReady());
    const mac = dev.macAddress();
    try std.testing.expectEqualSlices(u8, &.{ 0x52, 0x54, 0, 0x12, 0x34, 0x56 }, &mac);

    try dev.sendFrame(&.{1});
    var buf: [8]u8 = undefined;
    const n = try dev.pollRecv(&buf, 1);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2 }, buf[0..2]);
}
