const std = @import("std");
const index = @import("virtio_queue_index");

test "avail slot wraps by queue size" {
    try std.testing.expectEqual(@as(usize, 0), index.slot(8, 0));
    try std.testing.expectEqual(@as(usize, 7), index.slot(8, 7));
    try std.testing.expectEqual(@as(usize, 0), index.slot(8, 8));
    try std.testing.expectEqual(@as(usize, 3), index.slot(8, 11));
}

test "u16 ring index advances with wrapping arithmetic" {
    try std.testing.expectEqual(@as(u16, 1), index.advance(0));
    try std.testing.expectEqual(@as(u16, 0), index.advance(0xFFFF));
}

test "used index comparison detects pending completions" {
    try std.testing.expect(!index.hasUsed(10, 10));
    try std.testing.expect(index.hasUsed(11, 10));
    try std.testing.expect(index.hasUsed(0, 0xFFFF));
}
