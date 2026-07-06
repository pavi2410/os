/// Pure DNS message helpers (no syscalls; host-testable).
const bytes = @import("common_bytes");

pub const Answer = struct {
    name_off: usize,
    rtype: u16,
    class: u16,
    ttl: u32,
    rdata: []const u8,
};

pub const AnswerIterator = struct {
    pkt: []const u8,
    off: usize,
    remaining: u16,

    pub fn next(self: *AnswerIterator) ?Answer {
        if (self.remaining == 0) return null;
        const name_off = self.off;
        self.off = skipName(self.pkt, self.off) orelse return null;
        if (self.off + 10 > self.pkt.len) return null;

        const rtype = bytes.readU16Be(self.pkt, self.off);
        const class = bytes.readU16Be(self.pkt, self.off + 2);
        const ttl = bytes.readU32Be(self.pkt, self.off + 4);
        const rdlen = bytes.readU16Be(self.pkt, self.off + 8);
        self.off += 10;
        if (self.off + rdlen > self.pkt.len) return null;

        const rdata = self.pkt[self.off .. self.off + rdlen];
        self.off += rdlen;
        self.remaining -= 1;

        return .{
            .name_off = name_off,
            .rtype = rtype,
            .class = class,
            .ttl = ttl,
            .rdata = rdata,
        };
    }
};

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
    var iter = answers(pkt) orelse return false;
    while (iter.next()) |answer| {
        if (answer.rtype == 1 and answer.rdata.len == 4) {
            @memcpy(out, answer.rdata);
            return true;
        }
    }
    return false;
}

pub fn answers(pkt: []const u8) ?AnswerIterator {
    if (pkt.len < 12) return null;
    const qdcount = bytes.readU16Be(pkt, 4);
    const ancount = bytes.readU16Be(pkt, 6);

    var off: usize = 12;
    var qi: usize = 0;
    while (qi < qdcount) : (qi += 1) {
        off = skipName(pkt, off) orelse return null;
        if (off + 4 > pkt.len) return null;
        off += 4;
    }

    return .{
        .pkt = pkt,
        .off = off,
        .remaining = ancount,
    };
}

pub fn answerCount(pkt: []const u8) u16 {
    if (pkt.len < 8) return 0;
    return bytes.readU16Be(pkt, 6);
}

pub fn formatName(pkt: []const u8, off: usize, out: []u8) ?[]const u8 {
    var pos = off;
    var len: usize = 0;
    var steps: usize = 0;
    while (steps < 128) : (steps += 1) {
        if (pos >= pkt.len) return null;
        const len_byte = pkt[pos];
        if (len_byte == 0) break;
        if ((len_byte & 0xC0) == 0xC0) {
            if (pos + 1 >= pkt.len) return null;
            pos = (@as(usize, len_byte & 0x3F) << 8) | pkt[pos + 1];
            continue;
        }
        pos += 1;
        if (pos + len_byte > pkt.len) return null;
        if (len != 0) {
            if (len >= out.len) return null;
            out[len] = '.';
            len += 1;
        }
        if (len + len_byte > out.len) return null;
        @memcpy(out[len .. len + len_byte], pkt[pos .. pos + len_byte]);
        len += len_byte;
        pos += len_byte;
    }
    return out[0..len];
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
