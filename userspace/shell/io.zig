const libc = @import("libc");

pub fn writeStr(s: []const u8) void {
    _ = libc.syscall.write(1, s.ptr, s.len);
}

pub fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (x != y) return false;
    }
    return true;
}

pub fn writeChar(ch: u8) void {
    var buf: [1]u8 = .{ch};
    writeStr(&buf);
}

pub fn writeNewline() void {
    writeStr("\n");
}
