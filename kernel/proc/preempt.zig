//! Preemption disable counter (uniprocessor).
//! Blocks involuntary preemption only; see `scheduler.canPreempt`.
//!
//! The active counter is switched with the current thread so a
//! `preemptDisable` held across `switchTo` does not poison the next thread.

var bootstrap_count: usize = 0;
var current_count: *usize = &bootstrap_count;

/// Point the active counter at this thread's `preempt_count` field.
pub fn setCurrentCount(ptr: *usize) void {
    current_count = ptr;
}

pub fn disable() void {
    current_count.* += 1;
}

pub fn enable() void {
    if (current_count.* == 0) return;
    current_count.* -= 1;
}

pub fn count() usize {
    return current_count.*;
}

pub fn canPreempt() bool {
    return current_count.* == 0;
}

pub fn clearCurrent() void {
    current_count = &bootstrap_count;
}

pub fn resetForTest() void {
    bootstrap_count = 0;
    current_count = &bootstrap_count;
}
