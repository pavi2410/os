var last_exit: u8 = 0;

pub fn get() u8 {
    return last_exit;
}

pub fn set(code: u8) void {
    last_exit = code;
}

pub fn setFromWait(wstatus: u32) void {
    last_exit = codeFromWait(wstatus);
}

pub fn codeFromWait(wstatus: u32) u8 {
    return @truncate((wstatus >> 8) & 0xff);
}

/// Format exit code as decimal into `out`; returns written slice.
pub fn formatTo(out: []u8) ?[]const u8 {
    return formatCode(get(), out);
}

pub fn formatCode(code: u8, out: []u8) ?[]const u8 {
    if (out.len == 0) return null;
    if (code == 0) {
        out[0] = '0';
        return out[0..1];
    }

    var tmp: [3]u8 = undefined;
    var value: u8 = code;
    var len: usize = 0;
    while (value > 0) : (len += 1) {
        tmp[len] = '0' + (value % 10);
        value /= 10;
    }
    if (len > out.len) return null;

    var i: usize = 0;
    while (i < len) : (i += 1) {
        out[i] = tmp[len - 1 - i];
    }
    return out[0..len];
}
