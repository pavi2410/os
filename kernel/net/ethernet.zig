const mac = @import("common_mac");

pub const header_len = 14;
pub const min_frame_len = 60;
pub const max_frame_len = 1518;

pub const Ethertype = enum(u16) {
    ipv4 = 0x0800,
    arp = 0x0806,

    pub inline fn toBe(self: Ethertype) u16 {
        return @byteSwap(@intFromEnum(self));
    }

    pub inline fn fromHost(host: u16) ?Ethertype {
        return switch (host) {
            @intFromEnum(Ethertype.ipv4) => .ipv4,
            @intFromEnum(Ethertype.arp) => .arp,
            else => null,
        };
    }
};

comptime {
    if (@intFromEnum(Ethertype.ipv4) != 0x0800) @compileError("Ethertype.ipv4 must be 0x0800");
    if (@intFromEnum(Ethertype.arp) != 0x0806) @compileError("Ethertype.arp must be 0x0806");
}

pub const Header = extern struct {
    dst: mac.Mac,
    src: mac.Mac,
    ethertype_be: u16,
};

pub fn headerEthertype(hdr: *const Header) ?Ethertype {
    return Ethertype.fromHost(@byteSwap(hdr.ethertype_be));
}

pub fn putHeader(buf: []u8, dst_mac: mac.Mac, src_mac: mac.Mac, etype: Ethertype) void {
    @memcpy(buf[0..mac.len], &dst_mac.octets);
    @memcpy(buf[mac.len..][0..mac.len], &src_mac.octets);
    const host = @intFromEnum(etype);
    buf[12] = @truncate(host >> 8);
    buf[13] = @truncate(host);
}
