const syscall = @import("syscall.zig");
const format = @import("format.zig");

pub fn cstr(ptr: [*]u8) []const u8 {
    var len: usize = 0;
    while (len < 256) : (len += 1) {
        if (ptr[len] == 0) return ptr[0..len];
    }
    return ptr[0..256];
}

pub fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (x != y) return false;
    }
    return true;
}

pub fn writeStr(s: []const u8) void {
    _ = syscall.write(1, s.ptr, s.len);
}

pub fn writeChar(ch: u8) void {
    var buf: [1]u8 = .{ch};
    writeStr(&buf);
}

pub fn writeDecimal(n: usize) void {
    var buf: [20]u8 = undefined;
    const text = format.decimal(n, &buf) orelse return;
    writeStr(text);
}

pub fn formatDecimal(n: usize, out: []u8) ?[]const u8 {
    return format.decimal(n, out);
}
