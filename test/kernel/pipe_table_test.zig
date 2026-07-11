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

test "duplicate references saturate without wrapping endpoint ownership" {
    var table: pipe.PipeTable = .{};
    const handle = try table.create();

    var i: usize = 0;
    while (i < std.math.maxInt(u8)) : (i += 1) table.dupRef(handle, true);
    table.dupRef(handle, true);

    // It takes 255 closes to exhaust the initial read endpoint plus every
    // retained reference. A wrapped count would invalidate it much earlier.
    i = 0;
    while (i < std.math.maxInt(u8)) : (i += 1) table.closeRead(handle);
    try std.testing.expectError(error.WouldBlock, table.read(handle, &.{}));
}
