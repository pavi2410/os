const std = @import("std");
const filesystem = @import("filesystem");

test "file identity compares filesystem-neutral handles" {
    const a: filesystem.FileId = .{ .a = 10, .b = 20 };
    const same: filesystem.FileId = .{ .a = 10, .b = 20 };
    const different: filesystem.FileId = .{ .a = 10, .b = 21 };

    try std.testing.expect(a.eql(same));
    try std.testing.expect(!a.eql(different));
}

test "open file exposes directory bit without FAT32 type leak" {
    const dir: filesystem.OpenFile = .{ .attr = 0x10 };
    const file: filesystem.OpenFile = .{ .attr = 0x20 };

    try std.testing.expect(dir.isDirectory());
    try std.testing.expect(!file.isDirectory());
}

test "liftFat coerces shared fat32 errors into filesystem errors" {
    try std.testing.expectEqual(filesystem.Error.NotFound, filesystem.liftFat(filesystem.FatError.NotFound));
    try std.testing.expectEqual(filesystem.Error.NoSpace, filesystem.liftFat(filesystem.FatError.NoSpace));
}

test "errnoCode maps filesystem errors to linux errno values" {
    try std.testing.expectEqual(@as(i64, -2), filesystem.errnoCode(filesystem.Error.NotFound));
    try std.testing.expectEqual(@as(i64, -21), filesystem.errnoCode(filesystem.Error.IsDirectory));
    try std.testing.expectEqual(@as(i64, -9), filesystem.errnoCode(filesystem.Error.BadHandle));
    try std.testing.expectEqual(@as(i64, -5), filesystem.errnoCode(filesystem.Error.InvalidBpb));
    try std.testing.expectEqual(@as(i64, -13), filesystem.errnoCode(filesystem.Error.ReadOnly));
    try std.testing.expectEqual(@as(i64, -22), filesystem.errnoCode(filesystem.Error.NameTooLong));
    try std.testing.expectEqual(@as(i64, -16), filesystem.errnoCode(filesystem.Error.Busy));
    try std.testing.expectEqual(@as(i64, -95), filesystem.errnoCode(filesystem.Error.NotSupported));
}

test "open flags pack into a single byte" {
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(filesystem.OpenFlags));

    const flags = filesystem.OpenFlags{
        .read = true,
        .write = true,
        .create = true,
        .truncate = false,
        .append = true,
    };
    try std.testing.expect(flags.read);
    try std.testing.expect(flags.write);
    try std.testing.expect(flags.create);
    try std.testing.expect(!flags.truncate);
    try std.testing.expect(flags.append);
}
