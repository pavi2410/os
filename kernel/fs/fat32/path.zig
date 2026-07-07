const std = @import("std");
const core = @import("core.zig");

pub const FatError = core.FatError;

pub fn lastIndexOf(hay: []const u8, needle: u8) ?usize {
    var i = hay.len;
    while (i > 0) : (i -= 1) {
        if (hay[i - 1] == needle) return i - 1;
    }
    return null;
}

pub fn parentName(clean: []const u8) []const u8 {
    if (lastIndexOf(clean, '/')) |slash| return clean[slash + 1 ..];
    return clean;
}

pub fn normalizePath(path: []const u8, out: []u8) FatError![]const u8 {
    if (path.len >= out.len) return FatError.PathTooLong;

    var len: usize = 0;
    var i: usize = 0;
    while (i < path.len) : (i += 1) {
        if (path[i] == '/') continue;
        const start = i;
        while (i < path.len and path[i] != '/') : (i += 1) {}
        const part = path[start..i];
        if (part.len == 0) continue;
        if (std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return FatError.NotFound;
        if (len != 0) {
            out[len] = '/';
            len += 1;
        }
        if (len + part.len >= out.len) return FatError.PathTooLong;
        @memcpy(out[len .. len + part.len], part);
        len += part.len;
        if (i < path.len and path[i] == '/') {}
    }
    return out[0..len];
}
