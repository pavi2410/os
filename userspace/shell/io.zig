const std = @import("std");
const ulib = @import("ulib");

pub fn writeStr(s: []const u8) void {
    ulib.io.writeStr(s);
}

pub fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub fn writeChar(ch: u8) void {
    var buf: [1]u8 = .{ch};
    writeStr(&buf);
}

pub fn writeNewline() void {
    writeStr("\n");
}
