/// Pure DNS message helpers (no syscalls; host-testable).
pub fn buildQuery(name: []const u8, out: []u8) !usize {
    if (out.len < 18) return error.BufferTooSmall;
    @memset(out[0..18], 0);
    out[0] = 0x12;
    out[1] = 0x34;
    out[2] = 0x01;
    out[3] = 0x00;
    out[4] = 0x00;
    out[5] = 0x01;

    const name_len = try encodeName(name, out[12..]);
    const tail = 12 + name_len;
    if (tail + 4 > out.len) return error.BufferTooSmall;
    out[tail] = 0x00;
    out[tail + 1] = 0x01;
    out[tail + 2] = 0x00;
    out[tail + 3] = 0x01;
    return tail + 4;
}

pub fn encodeName(name: []const u8, out: []u8) !usize {
    if (name.len == 0 or name[0] == '.') return error.BadName;
    var written: usize = 0;
    var label_start: usize = 0;
    var i: usize = 0;
    while (i <= name.len) : (i += 1) {
        const at_end = i == name.len;
        const ch = if (at_end) '.' else name[i];
        if (ch == '.') {
            const label_len = i - label_start;
            if (label_len == 0 or label_len > 63) return error.BadName;
            if (written + 1 + label_len > out.len) return error.BufferTooSmall;
            out[written] = @intCast(label_len);
            @memcpy(out[written + 1 .. written + 1 + label_len], name[label_start..i]);
            written += 1 + label_len;
            label_start = i + 1;
            continue;
        }
        if (ch < '0' or (ch > '9' and ch < 'A') or (ch > 'Z' and ch < 'a') or ch > 'z') {
            if (ch != '-') return error.BadName;
        }
    }
    if (written + 1 > out.len) return error.BufferTooSmall;
    out[written] = 0;
    return written + 1;
}

pub fn parseFirstA(pkt: []const u8, out: *[4]u8) bool {
    if (pkt.len < 12) return false;
    const qdcount = readU16(pkt, 4);
    const ancount = readU16(pkt, 6);
    if (ancount == 0) return false;

    var off: usize = 12;
    var qi: usize = 0;
    while (qi < qdcount) : (qi += 1) {
        off = skipName(pkt, off) orelse return false;
        off += 4;
        if (off > pkt.len) return false;
    }

    var ai: usize = 0;
    while (ai < ancount) : (ai += 1) {
        off = skipName(pkt, off) orelse return false;
        if (off + 10 > pkt.len) return false;
        const rtype = readU16(pkt, off);
        const rdlen = readU16(pkt, off + 8);
        off += 10;
        if (off + rdlen > pkt.len) return false;

        if (rtype == 1 and rdlen == 4) {
            @memcpy(out, pkt[off .. off + 4]);
            return true;
        }
        off += rdlen;
    }
    return false;
}

fn skipName(pkt: []const u8, off: usize) ?usize {
    var pos = off;
    var steps: usize = 0;
    while (steps < 128) : (steps += 1) {
        if (pos >= pkt.len) return null;
        const len_byte = pkt[pos];
        if (len_byte == 0) return pos + 1;
        if ((len_byte & 0xC0) == 0xC0) return pos + 2;
        pos += 1 + len_byte;
    }
    return null;
}

fn readU16(pkt: []const u8, off: usize) u16 {
    return (@as(u16, pkt[off]) << 8) | pkt[off + 1];
}
