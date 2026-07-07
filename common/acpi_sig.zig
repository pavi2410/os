const std = @import("std");

pub fn sigEq4At(table: []const u8, off: usize, comptime expected: *const [4]u8) bool {
    if (off + 4 > table.len) return false;
    return std.mem.eql(u8, table[off..][0..4], expected);
}

pub fn sigEq4Bytes(table: []const u8, off: usize, expected: [4]u8) bool {
    if (off + 4 > table.len) return false;
    return std.mem.eql(u8, table[off..][0..4], &expected);
}

pub fn sigEq8At(table: []const u8, off: usize, comptime expected: *const [8]u8) bool {
    if (off + 8 > table.len) return false;
    return std.mem.eql(u8, table[off..][0..8], expected);
}
