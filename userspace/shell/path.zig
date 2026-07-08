const path = @import("ulib").path;
const cwd = @import("cwd.zig");

pub fn resolve(input: []const u8, out: []u8) ?[]const u8 {
    return path.resolveAgainst(cwd.get(), input, out) catch null;
}

pub fn resolveAgainst(base: []const u8, input: []const u8, out: []u8) ?[]const u8 {
    return path.resolveAgainst(base, input, out) catch null;
}

pub fn join(dir: []const u8, name: []const u8, out: []u8) bool {
    _ = path.join(dir, name, out) catch return false;
    return true;
}

pub fn copy(path_str: []const u8, out: []u8) bool {
    if (path_str.len + 1 > out.len) return false;
    @memcpy(out[0..path_str.len], path_str);
    out[path_str.len] = 0;
    return true;
}
