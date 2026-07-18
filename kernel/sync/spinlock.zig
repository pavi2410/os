//! IRQ-safe spinlock for SMP shared data.
//!
//! Disables local interrupts while the lock is held so the holder cannot be
//! preempted into a nested path that tries to take the same lock. On host
//! unit tests (non-freestanding), interrupt save/restore is a nesting counter.

const std = @import("std");
const builtin = @import("builtin");

const is_kernel = builtin.os.tag == .freestanding;

pub const SpinLock = struct {
    /// 0 = unlocked, 1 = locked.
    state: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    /// Saved interrupt-enable flag (or host nesting token) for the holder.
    saved_flags: u64 = 0,

    pub fn lock(self: *SpinLock) void {
        const flags = Irq.saveAndDisable();
        while (self.state.cmpxchgWeak(0, 1, .acquire, .monotonic) != null) {
            std.atomic.spinLoopHint();
        }
        self.saved_flags = flags;
    }

    pub fn unlock(self: *SpinLock) void {
        const flags = self.saved_flags;
        self.saved_flags = 0;
        self.state.store(0, .release);
        Irq.restore(flags);
    }

    pub fn tryLock(self: *SpinLock) bool {
        const flags = Irq.saveAndDisable();
        if (self.state.cmpxchgStrong(0, 1, .acquire, .monotonic) != null) {
            Irq.restore(flags);
            return false;
        }
        self.saved_flags = flags;
        return true;
    }

    pub fn isLocked(self: *const SpinLock) bool {
        return self.state.load(.monotonic) != 0;
    }
};

const Irq = if (is_kernel) KernelIrq else HostIrq;

const KernelIrq = struct {
    fn saveAndDisable() u64 {
        var flags: u64 = undefined;
        asm volatile (
            \\pushfq
            \\popq %[flags]
            \\cli
            : [flags] "=r" (flags),
            :
            : .{ .memory = true }
        );
        return flags;
    }

    fn restore(flags: u64) void {
        asm volatile (
            \\pushq %[flags]
            \\popfq
            :
            : [flags] "r" (flags),
            : .{ .memory = true, .flags = true }
        );
    }
};

var host_irq_depth: u32 = 0;

const HostIrq = struct {
    fn saveAndDisable() u64 {
        const prev = host_irq_depth;
        host_irq_depth += 1;
        return prev;
    }

    fn restore(flags: u64) void {
        _ = flags;
        if (host_irq_depth == 0) return;
        host_irq_depth -= 1;
    }
};

pub fn resetHostIrqDepthForTest() void {
    if (comptime is_kernel) return;
    host_irq_depth = 0;
}
