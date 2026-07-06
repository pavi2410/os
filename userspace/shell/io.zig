const libc = @import("libc");

pub fn writeStr(s: []const u8) void {
    libc.io.writeStr(s);
}

pub fn eql(a: []const u8, b: []const u8) bool {
    return libc.io.eql(a, b);
}

pub fn writeChar(ch: u8) void {
    var buf: [1]u8 = .{ch};
    writeStr(&buf);
}

pub fn writeNewline() void {
    writeStr("\n");
}
