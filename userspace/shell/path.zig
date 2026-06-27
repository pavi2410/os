const io = @import("io.zig");

pub fn join(dir: []const u8, name: []const u8, out: []u8) bool {
    if (dir.len == 0 or name.len == 0) return false;
    var len: usize = 0;
    if (io.eql(dir, "/")) {
        if (1 + name.len + 1 > out.len) return false;
        out[0] = '/';
        len = 1;
    } else {
        if (dir.len + 1 + name.len + 1 > out.len) return false;
        @memcpy(out[0..dir.len], dir);
        out[dir.len] = '/';
        len = dir.len + 1;
    }
    @memcpy(out[len .. len + name.len], name);
    out[len + name.len] = 0;
    return true;
}

pub fn copy(path: []const u8, out: []u8) bool {
    if (path.len + 1 > out.len) return false;
    @memcpy(out[0..path.len], path);
    out[path.len] = 0;
    return true;
}
