const syscall = @import("syscall.zig");
const time_math = @import("time_math.zig");

pub const Timespec = syscall.Timespec;
pub const CLOCK_REALTIME = syscall.CLOCK_REALTIME;
pub const CLOCK_MONOTONIC = syscall.CLOCK_MONOTONIC;

pub fn clockGettime(clock_id: u32, out: *Timespec) isize {
    return syscall.clock_gettime(clock_id, out);
}

pub fn realtime(out: *Timespec) bool {
    return clockGettime(CLOCK_REALTIME, out) >= 0;
}

pub fn monotonic(out: *Timespec) bool {
    return clockGettime(CLOCK_MONOTONIC, out) >= 0;
}

pub fn monotonicUs() u64 {
    var ts: Timespec = undefined;
    if (!monotonic(&ts)) return 0;
    return timespecUs(ts);
}

pub fn elapsedUs(start_us: u64, now_us: u64) u64 {
    return time_math.elapsedUs(start_us, now_us);
}

pub fn timespecUs(ts: Timespec) u64 {
    return time_math.timespecUs(ts);
}
