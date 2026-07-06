pub fn readU16Be(buf: []const u8, off: usize) u16 {
    return (@as(u16, buf[off]) << 8) | buf[off + 1];
}

pub fn readU32Be(buf: []const u8, off: usize) u32 {
    return (@as(u32, buf[off]) << 24) |
        (@as(u32, buf[off + 1]) << 16) |
        (@as(u32, buf[off + 2]) << 8) |
        buf[off + 3];
}

pub fn writeU16Be(buf: []u8, off: usize, value: u16) void {
    buf[off] = @truncate(value >> 8);
    buf[off + 1] = @truncate(value);
}

pub fn writeU32Be(buf: []u8, off: usize, value: u32) void {
    buf[off] = @truncate(value >> 24);
    buf[off + 1] = @truncate(value >> 16);
    buf[off + 2] = @truncate(value >> 8);
    buf[off + 3] = @truncate(value);
}

pub fn readU16Le(buf: []const u8, off: usize) u16 {
    return @as(u16, buf[off]) | (@as(u16, buf[off + 1]) << 8);
}

pub fn readU32Le(buf: []const u8, off: usize) u32 {
    return @as(u32, buf[off]) |
        (@as(u32, buf[off + 1]) << 8) |
        (@as(u32, buf[off + 2]) << 16) |
        (@as(u32, buf[off + 3]) << 24);
}

pub fn writeU16Le(buf: []u8, off: usize, value: u16) void {
    buf[off] = @truncate(value);
    buf[off + 1] = @truncate(value >> 8);
}

pub fn writeU32Le(buf: []u8, off: usize, value: u32) void {
    buf[off] = @truncate(value);
    buf[off + 1] = @truncate(value >> 8);
    buf[off + 2] = @truncate(value >> 16);
    buf[off + 3] = @truncate(value >> 24);
}
