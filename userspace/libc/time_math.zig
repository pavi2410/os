pub fn elapsedUs(start_us: u64, now_us: u64) u64 {
    if (now_us < start_us) return 0;
    return now_us - start_us;
}

pub fn timespecUs(ts: anytype) u64 {
    if (ts.tv_sec < 0 or ts.tv_nsec < 0) return 0;
    return @as(u64, @intCast(ts.tv_sec)) * 1_000_000 + @as(u64, @intCast(ts.tv_nsec)) / 1000;
}
