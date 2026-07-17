const std = @import("std");
const mount = @import("mount");
const filesystem = @import("filesystem");

fn stubMount() filesystem.Error!void {}
fn stubReady() bool {
    return true;
}
fn stubOpen(_: []const u8, _: filesystem.OpenFlags) filesystem.Error!filesystem.OpenFile {
    return error.NotFound;
}
fn stubRead(_: filesystem.OpenFile, _: u64, _: []u8) filesystem.Error!usize {
    return 0;
}
fn stubWrite(_: *filesystem.OpenFile, _: u64, _: []const u8) filesystem.Error!usize {
    return 0;
}
fn stubStat(_: []const u8, _: *filesystem.Stat) filesystem.Error!void {
    return error.NotFound;
}
fn stubGetdents(_: filesystem.OpenFile, _: *usize, _: []u8) filesystem.Error!usize {
    return 0;
}
fn stubUnlink(_: []const u8) filesystem.Error!?filesystem.FileId {
    return null;
}
fn stubMkdir(_: []const u8) filesystem.Error!void {}
fn stubRmdir(_: []const u8) filesystem.Error!?filesystem.FileId {
    return null;
}

const fat_ops: filesystem.Ops = .{
    .name = "fat",
    .mount = stubMount,
    .is_ready = stubReady,
    .open = stubOpen,
    .read = stubRead,
    .write_at = stubWrite,
    .stat = stubStat,
    .getdents64 = stubGetdents,
    .unlink = stubUnlink,
    .mkdir = stubMkdir,
    .rmdir = stubRmdir,
};

const tmp_ops: filesystem.Ops = .{
    .name = "tmpfs",
    .mount = stubMount,
    .is_ready = stubReady,
    .open = stubOpen,
    .read = stubRead,
    .write_at = stubWrite,
    .stat = stubStat,
    .getdents64 = stubGetdents,
    .unlink = stubUnlink,
    .mkdir = stubMkdir,
    .rmdir = stubRmdir,
};

test "prefixMatches respects component boundaries" {
    try std.testing.expect(mount.prefixMatches("/", "/"));
    try std.testing.expect(mount.prefixMatches("/", "/BIN"));
    try std.testing.expect(mount.prefixMatches("/tmp", "/tmp"));
    try std.testing.expect(mount.prefixMatches("/tmp", "/tmp/foo"));
    try std.testing.expect(!mount.prefixMatches("/tmp", "/tmpfoo"));
    try std.testing.expect(!mount.prefixMatches("/tmp", "/tm"));
}

test "relativePath strips mount prefix" {
    try std.testing.expectEqualStrings("/", mount.relativePath("/tmp", "/tmp"));
    try std.testing.expectEqualStrings("/foo", mount.relativePath("/tmp", "/tmp/foo"));
    try std.testing.expectEqualStrings("/BIN/SHELL", mount.relativePath("/", "/BIN/SHELL"));
}

test "resolve picks longest matching mount" {
    var table: mount.Table = .{};
    try table.add("/", &fat_ops);
    try table.add("/tmp", &tmp_ops);

    const root = try table.resolve("/BIN/SHELL");
    try std.testing.expectEqualStrings("fat", root.ops.name);
    try std.testing.expectEqualStrings("/BIN/SHELL", root.rel_path);

    const tmp = try table.resolve("/tmp/foo");
    try std.testing.expectEqualStrings("tmpfs", tmp.ops.name);
    try std.testing.expectEqualStrings("/foo", tmp.rel_path);

    const tmp_root = try table.resolve("/tmp");
    try std.testing.expectEqualStrings("tmpfs", tmp_root.ops.name);
    try std.testing.expectEqualStrings("/", tmp_root.rel_path);
}

test "resolve rejects non-absolute paths" {
    var table: mount.Table = .{};
    try table.add("/", &fat_ops);
    try std.testing.expectError(mount.MountError.InvalidPath, table.resolve("BIN"));
    try std.testing.expectError(mount.MountError.InvalidPath, table.resolve(""));
}

test "add rejects bad mount paths" {
    var table: mount.Table = .{};
    try std.testing.expectError(mount.MountError.InvalidPath, table.add("tmp", &tmp_ops));
    try std.testing.expectError(mount.MountError.InvalidPath, table.add("/tmp/", &tmp_ops));
}
