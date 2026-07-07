pub fn parsePort(text: []const u8) ?u16 {
    if (text.len == 0 or text.len > 5) return null;
    var value: u16 = 0;
    for (text) |ch| {
        if (ch < '0' or ch > '9') return null;
        const digit: u16 = ch - '0';
        if (value > 6553 or (value == 6553 and digit > 5)) return null;
        value = value * 10 + digit;
    }
    if (value == 0) return null;
    return value;
}

pub fn parseDecimal(text: []const u8, max: ?usize) ?usize {
    if (text.len == 0) return null;
    var value: usize = 0;
    for (text) |ch| {
        if (ch < '0' or ch > '9') return null;
        value = value * 10 + (ch - '0');
        if (max) |limit| {
            if (value > limit) return null;
        }
    }
    if (value == 0) return null;
    return value;
}
