const std = @import("std");
const hex = @import("common/hex");

pub const len = 6;

/// Ethernet hardware address (EUI-48).
pub const Mac = extern struct {
    octets: [len]u8 align(1),

    /// Buffer size for `formatBuf` (`aa:bb:cc:dd:ee:ff`).
    pub const format_len = len * 3 - 1;

    pub const zero = init(0, 0, 0, 0, 0, 0);
    pub const broadcast = init(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF);

    pub inline fn init(a: u8, b: u8, c: u8, d: u8, e: u8, f: u8) Mac {
        return .{ .octets = .{ a, b, c, d, e, f } };
    }

    pub inline fn fromOctets(octets: [len]u8) Mac {
        return .{ .octets = octets };
    }

    pub inline fn fromU48(value: u48) Mac {
        return .{ .octets = @bitCast(value) };
    }

    pub inline fn toU48(self: Mac) u48 {
        return @bitCast(self.octets);
    }

    pub fn parse(comptime text: []const u8) Mac {
        return comptime blk: {
            if (text.len == 17) {
                var octets: [len]u8 = undefined;
                var byte_idx: usize = 0;
                var i: usize = 0;
                while (byte_idx < len) : (byte_idx += 1) {
                    if (byte_idx > 0) {
                        if (text[i] != ':') @compileError("expected ':' in MAC address");
                        i += 1;
                    }
                    octets[byte_idx] = (hex.hexCharToNibble(text[i]) << 4) | hex.hexCharToNibble(text[i + 1]);
                    i += 2;
                }
                if (i != text.len) @compileError("trailing characters in MAC address");
                break :blk .{ .octets = octets };
            }
            if (text.len == 12) {
                var octets: [len]u8 = undefined;
                var byte_idx: usize = 0;
                var i: usize = 0;
                while (byte_idx < len) : (byte_idx += 1) {
                    octets[byte_idx] = (hex.hexCharToNibble(text[i]) << 4) | hex.hexCharToNibble(text[i + 1]);
                    i += 2;
                }
                break :blk .{ .octets = octets };
            }
            @compileError("expected 17-char (aa:bb:cc:dd:ee:ff) or 12-char hex MAC");
        };
    }

    pub inline fn eql(self: Mac, other: Mac) bool {
        return self.toU48() == other.toU48();
    }

    pub inline fn isBroadcast(self: Mac) bool {
        return self.eql(broadcast);
    }

    pub fn formatBuf(self: Mac, buf: []u8) ?[]const u8 {
        return hex.formatColonHex(&self.octets, buf);
    }

    pub fn format(self: Mac, w: *std.Io.Writer) std.Io.Writer.Error!void {
        var buf: [format_len]u8 = undefined;
        const s = self.formatBuf(&buf) orelse return error.WriteFailed;
        try w.writeAll(s);
    }
};

comptime {
    if (@sizeOf(Mac) != len) @compileError("Mac must be 6 bytes");
    if (!Mac.parse("52:54:00:12:34:56").eql(Mac.init(0x52, 0x54, 0x00, 0x12, 0x34, 0x56))) {
        @compileError("Mac.parse must accept colon-separated addresses");
    }
    if (!Mac.parse("525400123456").eql(Mac.init(0x52, 0x54, 0x00, 0x12, 0x34, 0x56))) {
        @compileError("Mac.parse must accept compact hex addresses");
    }
}
