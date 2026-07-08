const std = @import("std");
const devfs = @import("devfs");
const filesystem = @import("filesystem");

test "lookup resolves static device nodes" {
    const root = devfs.lookup("/dev").?;
    try std.testing.expect(root == .root);

    const null_node = devfs.lookup("/dev/null").?;
    try std.testing.expectEqual(devfs.Device.null_dev, null_node.device);

    const zero_node = devfs.lookup("/dev/zero").?;
    try std.testing.expectEqual(devfs.Device.zero_dev, zero_node.device);

    const tty_node = devfs.lookup("/dev/ttyS0").?;
    try std.testing.expectEqual(devfs.Device.tty_dev, tty_node.device);

    try std.testing.expect(devfs.lookup("/dev/missing") == null);
}

test "stat reports character devices" {
    var st: filesystem.Stat = .{};
    devfs.stat(.{ .device = .null_dev }, &st);
    try std.testing.expect(st.st_mode & 0o170000 == 0o020000);
    try std.testing.expectEqual(@as(u64, @intFromEnum(devfs.Device.null_dev)), st.st_rdev);
}

test "null device discards writes and returns eof on read" {
    var buf: [8]u8 = .{1} ** 8;
    try std.testing.expectEqual(@as(usize, 0), devfs.readDevice(.null_dev, &buf));
    try std.testing.expectEqual(@as(usize, 9), devfs.writeDevice(.null_dev, "discarded"));
}

test "zero device returns zero-filled reads" {
    var buf: [4]u8 = .{0xFF} ** 4;
    try std.testing.expectEqual(@as(usize, 4), devfs.readDevice(.zero_dev, &buf));
    try std.testing.expectEqual(@as(u8, 0), buf[0]);
    try std.testing.expectEqual(@as(u8, 0), buf[3]);
}

test "getdents64 lists device directory entries" {
    var buf: [512]u8 = undefined;
    var skip: usize = 0;
    const n = try devfs.getdents64(&skip, &buf);
    try std.testing.expect(n > 0);
    try std.testing.expect(std.mem.indexOf(u8, buf[0..n], "null") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf[0..n], "zero") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf[0..n], "ttyS0") != null);
}
