pub fn decimal(n: usize, out: []u8) ?[]const u8 {
    if (out.len == 0) return null;
    if (n == 0) {
        out[0] = '0';
        return out[0..1];
    }

    var tmp: [20]u8 = undefined;
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
