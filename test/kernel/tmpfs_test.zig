const std = @import("std");
const tmpfs = @import("tmpfs");
const filesystem = @import("filesystem");

fn mountFresh() !void {
    tmpfs.resetForTest();
    try tmpfs.ops.mount();
    try std.testing.expect(tmpfs.ops.is_ready());
}

test "tmpfs create write read unlink" {
    try mountFresh();
    const flags = filesystem.OpenFlags{ .read = true, .write = true, .create = true };
    var file = try tmpfs.ops.open("/hello.txt", flags);
    const msg = "hello tmpfs";
    const n = try tmpfs.ops.write_at(&file, 0, msg);
    try std.testing.expectEqual(msg.len, n);

    var buf: [32]u8 = undefined;
    const got = try tmpfs.ops.read(file, 0, &buf);
    try std.testing.expectEqual(msg.len, got);
    try std.testing.expectEqualStrings(msg, buf[0..got]);

    _ = try tmpfs.ops.unlink("/hello.txt");
    try std.testing.expectError(filesystem.Error.NotFound, tmpfs.ops.open("/hello.txt", .{ .read = true }));
}

test "tmpfs mkdir and getdents" {
    try mountFresh();
    try tmpfs.ops.mkdir("/dir");
    _ = try tmpfs.ops.open("/dir/a.txt", .{ .read = true, .write = true, .create = true });

    const dir = try tmpfs.ops.open("/dir", .{ .read = true });
    var skip: usize = 0;
    var buf: [512]u8 = undefined;
    const n = try tmpfs.ops.getdents64(dir, &skip, &buf);
    try std.testing.expect(n > 0);

    var found = false;
    var it = @import("abi_fs").Dirent64Iterator{ .data = buf[0..n] };
    while (it.next()) |ent| {
        if (std.mem.eql(u8, ent.name, "a.txt")) found = true;
    }
    try std.testing.expect(found);
}

test "tmpfs rmdir rejects non-empty" {
    try mountFresh();
    try tmpfs.ops.mkdir("/d");
    _ = try tmpfs.ops.open("/d/f", .{ .read = true, .write = true, .create = true });
    try std.testing.expectError(filesystem.Error.NotEmpty, tmpfs.ops.rmdir("/d"));
    _ = try tmpfs.ops.unlink("/d/f");
    _ = try tmpfs.ops.rmdir("/d");
}

test "tmpfs stat reports mode and size" {
    try mountFresh();
    var file = try tmpfs.ops.open("/s", .{ .read = true, .write = true, .create = true });
    _ = try tmpfs.ops.write_at(&file, 0, "abcd");
    var st: filesystem.Stat = .{};
    try tmpfs.ops.stat("/s", &st);
    try std.testing.expectEqual(@as(i64, 4), st.st_size);
    try std.testing.expectEqual(filesystem.ModeType.reg, filesystem.ModeType.fromMode(st.st_mode).?);
}

test "tmpfs rename and symlink round-trip" {
    try mountFresh();
    _ = try tmpfs.ops.open("/a", .{ .read = true, .write = true, .create = true });
    try tmpfs.ops.rename.?("/a", "/b");
    try std.testing.expectError(filesystem.Error.NotFound, tmpfs.ops.open("/a", .{ .read = true }));
    _ = try tmpfs.ops.open("/b", .{ .read = true });

    try tmpfs.ops.symlink.?("/b", "/link");
    var buf: [8]u8 = undefined;
    const n = try tmpfs.ops.readlink.?("/link", &buf);
    try std.testing.expectEqualStrings("/b", buf[0..n]);
}
