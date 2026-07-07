const std = @import("std");

pub fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub fn startsWith(haystack: []const u8, prefix: []const u8) bool {
    return std.mem.startsWith(u8, haystack, prefix);
}

pub fn indexOf(haystack: []const u8, needle: []const u8) ?usize {
    return std.mem.indexOf(u8, haystack, needle);
}

pub fn indexOfScalar(haystack: []const u8, ch: u8) ?usize {
    return std.mem.indexOfScalar(u8, haystack, ch);
}

pub fn lastIndexOfScalar(haystack: []const u8, ch: u8) ?usize {
    return std.mem.lastIndexOfScalar(u8, haystack, ch);
}
