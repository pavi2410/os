pub fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (x != y) return false;
    }
    return true;
}

pub fn startsWith(haystack: []const u8, prefix: []const u8) bool {
    return haystack.len >= prefix.len and eql(haystack[0..prefix.len], prefix);
}

pub fn indexOf(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0 or haystack.len < needle.len) return null;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (eql(haystack[i..][0..needle.len], needle)) return i;
    }
    return null;
}

pub fn indexOfScalar(haystack: []const u8, ch: u8) ?usize {
    for (haystack, 0..) |c, i| {
        if (c == ch) return i;
    }
    return null;
}

pub fn lastIndexOfScalar(haystack: []const u8, ch: u8) ?usize {
    var i = haystack.len;
    while (i > 0) {
        i -= 1;
        if (haystack[i] == ch) return i;
    }
    return null;
}
