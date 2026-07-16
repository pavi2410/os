const std = @import("std");
const status = @import("status");

test "codeFromWait decodes normal exit" {
    try std.testing.expectEqual(@as(u8, 0), status.codeFromWait(0));
    try std.testing.expectEqual(@as(u8, 1), status.codeFromWait(1 << 8));
    try std.testing.expectEqual(@as(u8, 127), status.codeFromWait(127 << 8));
}

test "codeFromWait decodes signal death as 128+signum" {
    // SIGINT = 2 → wait status 2 → shell $? = 130
    try std.testing.expectEqual(@as(u8, 130), status.codeFromWait(2));
    try std.testing.expectEqual(@as(u8, 143), status.codeFromWait(15)); // SIGTERM
}
