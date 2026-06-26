const std = @import("std");

pub fn get(path: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, path, "/hello") or std.mem.eql(u8, path, "hello")) {
        return hello;
    }
    if (std.mem.eql(u8, path, "/shell") or std.mem.eql(u8, path, "shell")) {
        return shell;
    }
    return null;
}

pub const hello = @embedFile("bins/hello");
pub const shell = @embedFile("bins/shell");
