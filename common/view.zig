pub fn mut(comptime T: type, buf: []u8, off: usize) ?*T {
    if (off > buf.len) return null;
    const avail = buf.len - off;
    if (avail < @sizeOf(T)) return null;
    return @ptrCast(@alignCast(buf.ptr + off));
}

pub fn get(comptime T: type, buf: []const u8, off: usize) ?*const T {
    if (off > buf.len) return null;
    const avail = buf.len - off;
    if (avail < @sizeOf(T)) return null;
    return @ptrCast(@alignCast(buf.ptr + off));
}
