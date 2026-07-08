pub fn nibbleToHexLower(n: u4) u8 {
    const v: u8 = @intCast(n);
    return if (v < 10) '0' + v else 'a' + (v - 10);
}

pub fn hexCharToNibble(comptime ch: u8) u8 {
    return switch (ch) {
        '0'...'9' => ch - '0',
        'a'...'f' => ch - 'a' + 10,
        'A'...'F' => ch - 'A' + 10,
        else => @compileError("invalid hex digit"),
    };
}

/// Format `bytes` as lowercase hex pairs separated by `sep`. Returns null if `buf` is too small.
pub fn formatSepHex(bytes: []const u8, sep: u8, buf: []u8) ?[]const u8 {
    if (bytes.len == 0) return buf[0..0];
    const need = bytes.len * 3 - 1;
    if (buf.len < need) return null;

    var i: usize = 0;
    for (bytes, 0..) |b, idx| {
        if (idx > 0) {
            buf[i] = sep;
            i += 1;
        }
        buf[i] = nibbleToHexLower(@truncate(b >> 4));
        buf[i + 1] = nibbleToHexLower(@truncate(b & 0xF));
        i += 2;
    }
    return buf[0..i];
}

pub fn formatColonHex(bytes: []const u8, buf: []u8) ?[]const u8 {
    return formatSepHex(bytes, ':', buf);
}
