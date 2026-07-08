const ip = @import("common_ipv4_addr");
const view = @import("common_view");

pub const header_len = 20;

pub const Protocol = enum(u8) {
    icmp = 1,
    tcp = 6,
    udp = 17,

    pub inline fn fromByte(byte: u8) ?Protocol {
        return switch (byte) {
            @intFromEnum(Protocol.icmp) => .icmp,
            @intFromEnum(Protocol.tcp) => .tcp,
            @intFromEnum(Protocol.udp) => .udp,
            else => null,
        };
    }
};

comptime {
    if (@intFromEnum(Protocol.icmp) != 1) @compileError("Protocol.icmp must be 1");
    if (@intFromEnum(Protocol.tcp) != 6) @compileError("Protocol.tcp must be 6");
    if (@intFromEnum(Protocol.udp) != 17) @compileError("Protocol.udp must be 17");
}

pub const Header = extern struct {
    version_ihl: u8,
    tos: u8,
    total_length_be: u16,
    identification_be: u16,
    flags_fragment_be: u16,
    ttl: u8,
    protocol: u8,
    checksum_be: u16,
    src: ip.Addr,
    dst: ip.Addr,
};

pub fn totalLengthHost(hdr: *const Header) u16 {
    return @byteSwap(hdr.total_length_be);
}

pub fn headerProtocol(hdr: *const Header) ?Protocol {
    return Protocol.fromByte(hdr.protocol);
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
    src: ip.Addr,
    dst: ip.Addr,
    protocol: Protocol,
    payload_len: u16,
) void {
    const hdr = view.mut(Header, buf, 0).?;
    hdr.version_ihl = 0x45;
    hdr.tos = 0;
    const total_len = header_len + payload_len;
    hdr.total_length_be = @byteSwap(total_len);
    hdr.identification_be = 0;
    hdr.flags_fragment_be = @byteSwap(@as(u16, 0x4000)); // don't fragment
    hdr.ttl = 64;
    hdr.protocol = @intFromEnum(protocol);
    hdr.checksum_be = 0;
    hdr.src = src;
    hdr.dst = dst;
    const csum = internetChecksum(buf[0..header_len]);
    hdr.checksum_be = @byteSwap(csum);
}
