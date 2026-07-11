const std = @import("std");
const pipe = @import("pipe");

test "independent pipe tables do not share handles or buffered bytes" {
    var left: pipe.PipeTable = .{};
    var right: pipe.PipeTable = .{};
    left.init();
    right.init();

    const left_handle = try left.create();
    const right_handle = try right.create();
    try std.testing.expectEqual(@as(u32, 0), left_handle);
    try std.testing.expectEqual(@as(u32, 0), right_handle);

    _ = try left.write(left_handle, "left");
    var buf: [8]u8 = undefined;
    try std.testing.expectError(error.WouldBlock, right.read(right_handle, &buf));
    try std.testing.expectEqual(@as(usize, 4), try left.read(left_handle, &buf));
    try std.testing.expectEqualStrings("left", buf[0..4]);
}

test "last endpoint release invalidates only its table entry" {
    var table: pipe.PipeTable = .{};
    const handle = try table.create();
    table.closeRead(handle);
    table.closeWrite(handle);
    try std.testing.expectError(error.BrokenPipe, table.read(handle, &.{}));
}
