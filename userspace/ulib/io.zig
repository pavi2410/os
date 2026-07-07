const syscall = @import("syscall.zig");
const format = @import("format.zig");
const string = @import("string.zig");

pub fn cstr(ptr: [*]u8) []const u8 {
    var len: usize = 0;
    while (len < 256) : (len += 1) {
        if (ptr[len] == 0) return ptr[0..len];
    }
    return ptr[0..256];
}

pub const eql = string.eql;

pub fn writeStr(s: []const u8) void {
    if (s.len == 0) return;
    _ = syscall.write(1, s.ptr, s.len);
}

pub fn readStdin(buf: []u8) isize {
    return syscall.read(0, buf.ptr, buf.len);
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

pub fn writeU32(n: u32) void {
    writeDecimal(@intCast(n));
}

pub fn writeU64(n: u64) void {
    var buf: [24]u8 = undefined;
    const text = format.decimalU64(n, &buf) orelse return;
    writeStr(text);
}

pub fn writeU8(n: u8) void {
    writeDecimal(n);
}

pub fn writeSignedDecimal(n: isize) void {
    if (n < 0) {
        writeChar('-');
        writeDecimal(@intCast(-n));
        return;
    }
    writeDecimal(@intCast(n));
}

pub fn writeMillis(us: u64) void {
    var buf: [24]u8 = undefined;
    const text = format.millis(us, &buf) orelse return;
    writeStr(text);
}

pub fn formatDecimal(n: usize, out: []u8) ?[]const u8 {
    return format.decimal(n, out);
}
