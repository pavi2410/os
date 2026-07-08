pub fn parseIpv4(text: []const u8, out: *[4]u8) bool {
    var part: u8 = 0;
    var idx: usize = 0;
    var saw_digit = false;
    var i: usize = 0;
    while (i <= text.len) : (i += 1) {
        if (i == text.len or text[i] == '.') {
            if (!saw_digit or idx >= 4) return false;
            out[idx] = part;
            idx += 1;
            part = 0;
            saw_digit = false;
            continue;
        }
        const ch = text[i];
        if (ch < '0' or ch > '9') return false;
        const next = @as(u16, part) * 10 + (ch - '0');
        if (next > 255) return false;
        part = @intCast(next);
        saw_digit = true;
    }
    return idx == 4;
}

pub fn formatIpv4(addr: [4]u8, out: []u8) ?[]const u8 {
    var pos: usize = 0;
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        if (i > 0) {
            if (pos >= out.len) return null;
            out[pos] = '.';
            pos += 1;
        }
        const written = formatU8Decimal(addr[i], out[pos..]) orelse return null;
        pos += written.len;
    }
    return out[0..pos];
}

pub fn formatMac(addr: [6]u8, out: []u8) ?[]const u8 {
    return @import("common_mac").Mac.fromOctets(addr).formatBuf(out);
}

pub fn networkAddr(addr: [4]u8, mask: [4]u8) [4]u8 {
    return .{
        addr[0] & mask[0],
        addr[1] & mask[1],
        addr[2] & mask[2],
        addr[3] & mask[3],
    };
}

pub fn maskPrefix(mask: [4]u8) u8 {
    var bits: u8 = 0;
    for (mask) |byte| {
        var bit: u8 = 0x80;
        while (bit != 0 and byte & bit != 0) : (bit >>= 1) {
            bits += 1;
        }
    }
    return bits;
}

fn formatU8Decimal(n: u8, out: []u8) ?[]const u8 {
    if (n >= 100) {
        if (out.len < 3) return null;
        out[0] = '0' + (n / 100);
        out[1] = '0' + ((n / 10) % 10);
        out[2] = '0' + (n % 10);
        return out[0..3];
    }
    if (n >= 10) {
        if (out.len < 2) return null;
        out[0] = '0' + (n / 10);
        out[1] = '0' + (n % 10);
        return out[0..2];
    }
    if (out.len < 1) return null;
    out[0] = '0' + n;
    return out[0..1];
}
