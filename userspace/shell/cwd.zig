var storage: [128]u8 = [_]u8{'/'} ++ [_]u8{0} ** 127;
var len: usize = 1;

pub fn get() []const u8 {
    return storage[0..len];
}

pub fn set(path: []const u8) bool {
    if (path.len == 0 or path.len + 1 > storage.len) return false;
    @memcpy(storage[0..path.len], path);
    storage[path.len] = 0;
    len = path.len;
    return true;
}
