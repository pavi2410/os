pub fn millis(us: u64, out: []u8) ?[]const u8 {
    var tmp: [20]u8 = undefined;
    const whole = decimal(@intCast(us / 1000), &tmp) orelse return null;
    const frac: u16 = @intCast(us % 1000);
    if (whole.len + 4 > out.len) return null;
    @memcpy(out[0..whole.len], whole);
    out[whole.len] = '.';
    out[whole.len + 1] = '0' + @as(u8, @intCast(frac / 100));
    out[whole.len + 2] = '0' + @as(u8, @intCast((frac / 10) % 10));
    out[whole.len + 3] = '0' + @as(u8, @intCast(frac % 10));
    return out[0 .. whole.len + 4];
}

pub fn decimal(n: usize, out: []u8) ?[]const u8 {
    return decimalU64(n, out);
}

pub fn decimalU64(n: u64, out: []u8) ?[]const u8 {
    if (out.len == 0) return null;
    if (n == 0) {
        out[0] = '0';
        return out[0..1];
    }

    var tmp: [24]u8 = undefined;
    var value = n;
    var len: usize = 0;
    while (value > 0) : (len += 1) {
        tmp[len] = '0' + @as(u8, @intCast(value % 10));
        value /= 10;
    }
    if (len > out.len) return null;

    var i: usize = 0;
    while (i < len) : (i += 1) {
        out[i] = tmp[len - 1 - i];
    }
    return out[0..len];
}
