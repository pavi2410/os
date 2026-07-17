const std = @import("std");
const preempt = @import("preempt");

test "preempt disable nests and sticky canPreempt" {
    preempt.resetForTest();
    defer preempt.resetForTest();

    try std.testing.expect(preempt.canPreempt());
    preempt.disable();
    try std.testing.expect(!preempt.canPreempt());
    preempt.disable();
    try std.testing.expectEqual(@as(usize, 2), preempt.count());
    preempt.enable();
    try std.testing.expect(!preempt.canPreempt());
    preempt.enable();
    try std.testing.expect(preempt.canPreempt());
}
