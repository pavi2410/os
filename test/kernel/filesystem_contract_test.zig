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
