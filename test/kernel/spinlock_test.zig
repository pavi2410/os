const std = @import("std");
const spinlock = @import("spinlock");

test "spinlock lock unlock" {
    spinlock.resetHostIrqDepthForTest();
    defer spinlock.resetHostIrqDepthForTest();

    var lock: spinlock.SpinLock = .{};
    try std.testing.expect(!lock.isLocked());
    lock.lock();
    try std.testing.expect(lock.isLocked());
    lock.unlock();
    try std.testing.expect(!lock.isLocked());
}

test "spinlock tryLock fails when held" {
    spinlock.resetHostIrqDepthForTest();
    defer spinlock.resetHostIrqDepthForTest();

    var lock: spinlock.SpinLock = .{};
    try std.testing.expect(lock.tryLock());
    try std.testing.expect(!lock.tryLock());
    lock.unlock();
    try std.testing.expect(lock.tryLock());
    lock.unlock();
}
