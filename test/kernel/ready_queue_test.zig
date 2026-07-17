const std = @import("std");
const ready_queue = @import("ready_queue");

const FakeThread = struct {
    id: usize,
    ready_next: ?*FakeThread = null,
};

test "ready queue push pop FIFO order" {
    var q: ready_queue.ReadyQueue(FakeThread) = .{};
    var a: FakeThread = .{ .id = 1 };
    var b: FakeThread = .{ .id = 2 };
    var c: FakeThread = .{ .id = 3 };

    try std.testing.expect(q.isEmpty());
    q.push(&a);
    q.push(&b);
    q.push(&c);
    try std.testing.expect(!q.isEmpty());

    try std.testing.expectEqual(@as(usize, 1), q.pop().?.id);
    try std.testing.expectEqual(@as(usize, 2), q.pop().?.id);
    try std.testing.expectEqual(@as(usize, 3), q.pop().?.id);
    try std.testing.expect(q.isEmpty());
    try std.testing.expect(q.pop() == null);
}

test "ready queue single element" {
    var q: ready_queue.ReadyQueue(FakeThread) = .{};
    var a: FakeThread = .{ .id = 7 };
    q.push(&a);
    try std.testing.expectEqual(@as(usize, 7), q.pop().?.id);
    try std.testing.expect(q.isEmpty());
    q.push(&a);
    try std.testing.expectEqual(@as(usize, 7), q.pop().?.id);
}
