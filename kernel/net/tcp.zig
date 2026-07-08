const bytes = @import("common/bytes");
const ethernet = @import("ethernet.zig");
const ipv4 = @import("ipv4.zig");
const ipv4_addr = @import("common/ipv4_addr");
const mac = @import("common/mac");

pub const header_len = 20;

pub const Header = extern struct {
    src_port_be: u16,
    dst_port_be: u16,
    seq_be: u32,
    ack_be: u32,
    data_offset_reserved: u8,
    flags: u8,
    window_be: u16,
    checksum_be: u16,
    urgent_be: u16,
};

pub const flag_fin: u8 = 0x01;
pub const flag_syn: u8 = 0x02;
pub const flag_rst: u8 = 0x04;
pub const flag_ack: u8 = 0x10;
pub const flag_psh: u8 = 0x08;

pub const default_window: u16 = 8192;

pub const Segment = struct {
    src_ip: ipv4_addr.Addr,
    dst_ip: ipv4_addr.Addr,
    src_port: u16,
    dst_port: u16,
    seq: u32,
    ack: u32,
    flags: u8,
    payload: []const u8,
};

pub fn srcPortHost(hdr: *const Header) u16 {
    return @byteSwap(hdr.src_port_be);
}

pub fn dstPortHost(hdr: *const Header) u16 {
    return @byteSwap(hdr.dst_port_be);
}

pub fn seqHost(hdr: *const Header) u32 {
    return @byteSwap(hdr.seq_be);
}

pub fn ackHost(hdr: *const Header) u32 {
    return @byteSwap(hdr.ack_be);
}

pub fn dataOffset(hdr: *const Header) u8 {
    return (hdr.data_offset_reserved >> 4) * 4;
}

pub fn checksum(src_ip: ipv4_addr.Addr, dst_ip: ipv4_addr.Addr, tcp: []const u8) u16 {
    var pseudo: [12]u8 = undefined;
    @memcpy(pseudo[0..4], &src_ip.octets);
    @memcpy(pseudo[4..8], &dst_ip.octets);
    pseudo[8] = 0;
    pseudo[9] = @intFromEnum(ipv4.Protocol.tcp);
    const tcp_len: u16 = @intCast(tcp.len);
    bytes.writeU16Be(&pseudo, 10, tcp_len);

    var sum: u32 = 0;
    inline for ([_]usize{ 0, 2, 4, 6, 8, 10 }) |off| {
        sum += bytes.readU16Be(&pseudo, off);
    }
    var i: usize = 0;
    while (i + 1 < tcp.len) : (i += 2) {
        sum += bytes.readU16Be(tcp, i);
    }
    if (i < tcp.len) {
        sum += @as(u32, tcp[i]) << 8;
    }
    while (sum >> 16 != 0) {
        sum = (sum & 0xFFFF) + (sum >> 16);
    }
    return @truncate(~sum);
}

pub fn build(
    out: []u8,
    dst_mac: mac.Mac,
    src_mac: mac.Mac,
    src_ip: ipv4_addr.Addr,
    dst_ip: ipv4_addr.Addr,
    src_port: u16,
    dst_port: u16,
    seq: u32,
    ack: u32,
    flags: u8,
    payload: []const u8,
) usize {
    const tcp_len: u16 = header_len + @as(u16, @intCast(payload.len));
    const ip_len = ipv4.header_len + tcp_len;
    var frame_len: usize = ethernet.header_len + ip_len;
    if (frame_len < ethernet.min_frame_len) frame_len = ethernet.min_frame_len;
    @memset(out[0..frame_len], 0);

    ethernet.putHeader(out, dst_mac, src_mac, ethernet.Ethertype.ipv4);
    ipv4.putHeader(out[ethernet.header_len..], src_ip, dst_ip, ipv4.Protocol.tcp, tcp_len);

    const tcp_off = ethernet.header_len + ipv4.header_len;
    bytes.writeU16Be(out, tcp_off, src_port);
    bytes.writeU16Be(out, tcp_off + 2, dst_port);
    bytes.writeU32Be(out, tcp_off + 4, seq);
    bytes.writeU32Be(out, tcp_off + 8, ack);
    out[tcp_off + 12] = 0x50; // 5 * 4 = 20 bytes
    out[tcp_off + 13] = flags;
    bytes.writeU16Be(out, tcp_off + 14, default_window);
    bytes.writeU16Be(out, tcp_off + 16, 0);
    bytes.writeU16Be(out, tcp_off + 18, 0);

    if (payload.len > 0) {
        @memcpy(out[tcp_off + header_len ..][0..payload.len], payload);
    }

    const tcp_slice = out[tcp_off .. tcp_off + tcp_len];
    const csum = checksum(src_ip, dst_ip, tcp_slice);
    bytes.writeU16Be(out, tcp_off + 16, csum);

    return frame_len;
}

pub fn parseSegment(frame: []const u8) ?Segment {
    if (frame.len < ethernet.header_len + ipv4.header_len + header_len) return null;

    if (ethernet.Ethertype.fromHost(bytes.readU16Be(frame, 12)) != .ipv4) return null;

    const ip_off = ethernet.header_len;
    if (ipv4.Protocol.fromByte(frame[ip_off + 9]) != .tcp) return null;

    const ip_total = bytes.readU16Be(frame, ip_off + 2);
    if (ip_total < ipv4.header_len + header_len) return null;
    const frame_ip_end = ethernet.header_len + ip_total;
    if (frame_ip_end > frame.len) return null;

    const tcp_off = ethernet.header_len + ipv4.header_len;
    if (tcp_off + header_len > frame.len) return null;
    const tcp_hdr_len = (frame[tcp_off + 12] >> 4) * 4;
    if (tcp_hdr_len < header_len) return null;
    if (tcp_off + tcp_hdr_len > frame_ip_end) return null;

    const payload_off = tcp_off + tcp_hdr_len;
    const payload_len = frame_ip_end - payload_off;
    if (payload_off + payload_len > frame.len) return null;

    var src_ip: ipv4_addr.Addr = undefined;
    var dst_ip: ipv4_addr.Addr = undefined;
    @memcpy(&src_ip.octets, frame[ip_off + 12 ..][0..ipv4_addr.len]);
    @memcpy(&dst_ip.octets, frame[ip_off + 16 ..][0..ipv4_addr.len]);

    return .{
        .src_ip = src_ip,
        .dst_ip = dst_ip,
        .src_port = bytes.readU16Be(frame, tcp_off),
        .dst_port = bytes.readU16Be(frame, tcp_off + 2),
        .seq = bytes.readU32Be(frame, tcp_off + 4),
        .ack = bytes.readU32Be(frame, tcp_off + 8),
        .flags = frame[tcp_off + 13],
        .payload = frame[payload_off .. payload_off + payload_len],
    };
}

pub fn matchEndpoint(
    frame: []const u8,
    local_port: u16,
    remote_ip: ipv4_addr.Addr,
    remote_port: u16,
) ?Segment {
    const seg = parseSegment(frame) orelse return null;
    if (seg.dst_port != local_port) return null;
    if (!seg.src_ip.eql(remote_ip)) return null;
    if (seg.src_port != remote_port) return null;
    return seg;
}
