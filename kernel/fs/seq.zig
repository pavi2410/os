//! Offset-aware helpers for generate-on-read pseudo files (procfs/sysfs).

/// Copy `data[offset..]` into `buf`. Returns bytes copied (0 at/after EOF).
pub fn readAt(data: []const u8, offset: u64, buf: []u8) usize {
    if (offset >= data.len or buf.len == 0) return 0;
    const off: usize = @intCast(offset);
    const take = @min(buf.len, data.len - off);
    @memcpy(buf[0..take], data[off..][0..take]);
    return take;
}

/// Append `src` to `dest` starting at `pos`. Returns new position (clamped to dest.len).
pub fn append(dest: []u8, pos: usize, src: []const u8) usize {
    if (pos >= dest.len or src.len == 0) return pos;
    const take = @min(src.len, dest.len - pos);
    @memcpy(dest[pos .. pos + take], src[0..take]);
    return pos + take;
}

/// Format `value` as decimal into `dest` starting at `pos`. Returns new position.
pub fn appendU64(dest: []u8, pos: usize, value: u64) usize {
    var digits: [20]u8 = undefined;
    var n = value;
    var count: usize = 0;
    if (n == 0) {
        digits[0] = '0';
        count = 1;
    } else {
        while (n > 0) : (n /= 10) {
            digits[count] = @truncate((n % 10) + '0');
            count += 1;
        }
    }
    var i = count;
    var p = pos;
    while (i > 0) : (i -= 1) {
        p = append(dest, p, digits[i - 1 .. i]);
    }
    return p;
}

const hex_digits = "0123456789abcdef";

/// Format `value` as zero-padded lowercase hex of `width` nibbles.
pub fn appendHex(dest: []u8, pos: usize, value: u64, width: usize) usize {
    var p = pos;
    var i: usize = 0;
    while (i < width) : (i += 1) {
        const shift: u6 = @intCast((width - 1 - i) * 4);
        const nibble: u8 = @truncate((value >> shift) & 0xF);
        p = append(dest, p, hex_digits[nibble .. nibble + 1]);
    }
    return p;
}
