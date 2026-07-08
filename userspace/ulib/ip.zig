const ip_addr = @import("common/ipv4_addr");

pub fn parseIpv4(text: []const u8, out: *[4]u8) bool {
    const parsed = ip_addr.Addr.parseText(text) orelse return false;
    out.* = parsed.octets;
    return true;
}

pub fn formatIpv4(addr: [4]u8, out: []u8) ?[]const u8 {
    return ip_addr.Addr.fromOctets(addr).formatBuf(out);
}

pub fn formatMac(addr: [6]u8, out: []u8) ?[]const u8 {
    return @import("common/mac").Mac.fromOctets(addr).formatBuf(out);
}

pub fn networkAddr(addr: [4]u8, mask: [4]u8) [4]u8 {
    return ip_addr.Addr.fromOctets(addr).networkWith(ip_addr.Addr.fromOctets(mask)).octets;
}

pub fn maskPrefix(mask: [4]u8) u8 {
    return ip_addr.Addr.prefixBits(ip_addr.Addr.fromOctets(mask));
}
