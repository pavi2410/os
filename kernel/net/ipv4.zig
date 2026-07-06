pub const addr_len = 4;
pub const header_len = 20;

pub const Addr = [addr_len]u8;

pub const proto_icmp: u8 = 1;

pub const Header = extern struct {
    version_ihl: u8,
    tos: u8,
    total_length_be: u16,
    identification_be: u16,
    flags_fragment_be: u16,
    ttl: u8,
    protocol: u8,
    checksum_be: u16,
    src: Addr,
    dst: Addr,
};

pub fn equal(a: Addr, b: Addr) bool {
    return @as(u32, @bitCast(a)) == @as(u32, @bitCast(b));
}

pub fn totalLengthHost(hdr: *const Header) u16 {
    return @byteSwap(hdr.total_length_be);
}

pub fn internetChecksum(data: []const u8) u16 {
    var sum: u32 = 0;
    var i: usize = 0;
    while (i + 1 < data.len) : (i += 2) {
        const word = (@as(u32, data[i]) << 8) | data[i + 1];
        sum += word;
    }
    if (i < data.len) {
        sum += @as(u32, data[i]) << 8;
    }
    while (sum >> 16 != 0) {
        sum = (sum & 0xFFFF) + (sum >> 16);
    }
    return @truncate(~sum);
}

pub fn putHeader(
    buf: []u8,
    src: Addr,
    dst: Addr,
    protocol: u8,
    payload_len: u16,
) void {
    const ip: *Header = @ptrCast(@alignCast(buf.ptr));
    ip.version_ihl = 0x45;
    ip.tos = 0;
    const total_len = header_len + payload_len;
    ip.total_length_be = @byteSwap(total_len);
    ip.identification_be = 0;
    ip.flags_fragment_be = @byteSwap(@as(u16, 0x4000)); // don't fragment
    ip.ttl = 64;
    ip.protocol = protocol;
    ip.checksum_be = 0;
    @memcpy(&ip.src, &src);
    @memcpy(&ip.dst, &dst);
    const csum = internetChecksum(buf[0..header_len]);
    ip.checksum_be = @byteSwap(csum);
}
