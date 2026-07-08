/// Return effective line length after stripping an unquoted `#` comment.
pub fn stripComment(buf: []u8, len: usize) usize {
    var i: usize = 0;
    var in_double = false;
    var escape = false;

    while (i < len) : (i += 1) {
        const ch = buf[i];
        if (escape) {
            escape = false;
            continue;
        }
        if (in_double) {
            if (ch == '\\') {
                escape = true;
            } else if (ch == '"') {
                in_double = false;
            }
            continue;
        }
        if (ch == '"') {
            in_double = true;
            continue;
        }
        if (ch == '#') return trimTrailing(buf, i);
    }

    return trimTrailing(buf, len);
}

fn trimTrailing(buf: []u8, end: usize) usize {
    var len = end;
    while (len > 0 and buf[len - 1] == ' ') len -= 1;
    return len;
}
