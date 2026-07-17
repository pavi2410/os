//! Preemption disable counter (uniprocessor).
//! Blocks involuntary preemption only; see `scheduler.canPreempt`.

var preempt_count: usize = 0;

pub fn disable() void {
    preempt_count += 1;
}

pub fn enable() void {
    if (preempt_count == 0) return;
    preempt_count -= 1;
}

pub fn count() usize {
    return preempt_count;
}

pub fn canPreempt() bool {
    return preempt_count == 0;
}

pub fn resetForTest() void {
    preempt_count = 0;
}
