const std = @import("std");

pub const len = 4;

/// IPv4 address.
pub const Addr = extern struct {
    octets: [len]u8 align(1),

    /// Buffer size for `formatBuf` (`ddd.ddd.ddd.ddd`).
    pub const format_len = 15;

    pub const zero = init(0, 0, 0, 0);

    pub inline fn init(a: u8, b: u8, c: u8, d: u8) Addr {
        return .{ .octets = .{ a, b, c, d } };
    }

    pub inline fn fromOctets(octets: [len]u8) Addr {
        return .{ .octets = octets };
    }

    pub inline fn fromU32(value: u32) Addr {
        return .{ .octets = @bitCast(value) };
    }

    pub inline fn toU32(self: Addr) u32 {
        return @bitCast(self.octets);
    }

    pub fn parse(comptime text: []const u8) Addr {
        return comptime blk: {
            var octets: [len]u8 = undefined;
            var part: u8 = 0;
            var idx: usize = 0;
            var saw_digit = false;
            var i: usize = 0;
            while (i <= text.len) : (i += 1) {
                if (i == text.len or text[i] == '.') {
                    if (!saw_digit or idx >= len) @compileError("invalid IPv4 address");
                    octets[idx] = part;
                    idx += 1;
                    part = 0;
                    saw_digit = false;
                    continue;
                }
                const ch = text[i];
                if (ch < '0' or ch > '9') @compileError("invalid IPv4 address");
                const next = @as(u16, part) * 10 + (ch - '0');
                if (next > 255) @compileError("invalid IPv4 address");
                part = @intCast(next);
                saw_digit = true;
            }
            if (idx != len) @compileError("invalid IPv4 address");
            break :blk .{ .octets = octets };
        };
    }

    pub fn parseText(text: []const u8) ?Addr {
        var part: u8 = 0;
        var idx: usize = 0;
        var saw_digit = false;
        var i: usize = 0;
        var octets: [len]u8 = undefined;
        while (i <= text.len) : (i += 1) {
            if (i == text.len or text[i] == '.') {
                if (!saw_digit or idx >= len) return null;
                octets[idx] = part;
                idx += 1;
                part = 0;
                saw_digit = false;
                continue;
            }
            const ch = text[i];
            if (ch < '0' or ch > '9') return null;
            const next = @as(u16, part) * 10 + (ch - '0');
            if (next > 255) return null;
            part = @intCast(next);
            saw_digit = true;
        }
        if (idx != len) return null;
        return .{ .octets = octets };
    }

    pub inline fn eql(self: Addr, other: Addr) bool {
        return self.toU32() == other.toU32();
    }

    pub inline fn sameSubnet(self: Addr, network: Addr, mask: Addr) bool {
        return (self.toU32() & mask.toU32()) == (network.toU32() & mask.toU32());
    }

    pub inline fn networkWith(self: Addr, mask: Addr) Addr {
        return fromU32(self.toU32() & mask.toU32());
    }

    pub fn prefixBits(mask: Addr) u8 {
        var bits: u8 = 0;
        for (mask.octets) |byte| {
            var bit: u8 = 0x80;
            while (bit != 0 and byte & bit != 0) : (bit >>= 1) {
                bits += 1;
            }
        }
        return bits;
    }

    pub fn formatBuf(self: Addr, buf: []u8) ?[]const u8 {
        if (buf.len < format_len) return null;
        var i: usize = 0;
        var octet: usize = 0;
        while (octet < len) : (octet += 1) {
            if (octet > 0) {
                buf[i] = '.';
                i += 1;
            }
            i += writeU8Decimal(self.octets[octet], buf[i..]);
        }
        return buf[0..i];
    }

    pub fn format(self: Addr, w: *std.Io.Writer) std.Io.Writer.Error!void {
        var buf: [format_len]u8 = undefined;
        const s = self.formatBuf(&buf) orelse return error.WriteFailed;
        try w.writeAll(s);
    }
};

comptime {
    if (@sizeOf(Addr) != len) @compileError("Addr must be 4 bytes");
    if (!Addr.parse("10.0.2.15").eql(Addr.init(10, 0, 2, 15))) {
        @compileError("Addr.parse must accept dotted decimal addresses");
    }
}

fn writeU8Decimal(n: u8, out: []u8) usize {
    if (n >= 100) {
        out[0] = '0' + (n / 100);
        out[1] = '0' + ((n / 10) % 10);
        out[2] = '0' + (n % 10);
        return 3;
    }
    if (n >= 10) {
        out[0] = '0' + (n / 10);
        out[1] = '0' + (n % 10);
        return 2;
    }
    out[0] = '0' + n;
    return 1;
}
