const ethernet = @import("ethernet.zig");
const ipv4 = @import("ipv4.zig");

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
    src_ip: ipv4.Addr,
    dst_ip: ipv4.Addr,
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

pub fn checksum(src_ip: ipv4.Addr, dst_ip: ipv4.Addr, tcp: []const u8) u16 {
    var pseudo: [12]u8 = undefined;
    @memcpy(pseudo[0..4], &src_ip);
    @memcpy(pseudo[4..8], &dst_ip);
    pseudo[8] = 0;
    pseudo[9] = ipv4.proto_tcp;
    const tcp_len: u16 = @intCast(tcp.len);
    pseudo[10] = @truncate(tcp_len >> 8);
    pseudo[11] = @truncate(tcp_len);

    var sum: u32 = 0;
    inline for ([_]usize{ 0, 2, 4, 6, 8, 10 }) |off| {
        const word = (@as(u32, pseudo[off]) << 8) | pseudo[off + 1];
        sum += word;
    }
    var i: usize = 0;
    while (i + 1 < tcp.len) : (i += 2) {
        const word = (@as(u32, tcp[i]) << 8) | tcp[i + 1];
        sum += word;
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
    dst_mac: ethernet.Mac,
    src_mac: ethernet.Mac,
    src_ip: ipv4.Addr,
    dst_ip: ipv4.Addr,
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

    ethernet.putHeader(out, dst_mac, src_mac, ethernet.ethertype_ipv4);
    ipv4.putHeader(out[ethernet.header_len..], src_ip, dst_ip, ipv4.proto_tcp, tcp_len);

    const tcp_off = ethernet.header_len + ipv4.header_len;
    writeU16Be(out, tcp_off, src_port);
    writeU16Be(out, tcp_off + 2, dst_port);
    writeU32Be(out, tcp_off + 4, seq);
    writeU32Be(out, tcp_off + 8, ack);
    out[tcp_off + 12] = 0x50; // 5 * 4 = 20 bytes
    out[tcp_off + 13] = flags;
    writeU16Be(out, tcp_off + 14, default_window);
    writeU16Be(out, tcp_off + 16, 0);
    writeU16Be(out, tcp_off + 18, 0);

    if (payload.len > 0) {
        @memcpy(out[tcp_off + header_len ..][0..payload.len], payload);
    }

    const tcp_slice = out[tcp_off .. tcp_off + tcp_len];
    const csum = checksum(src_ip, dst_ip, tcp_slice);
    writeU16Be(out, tcp_off + 16, csum);

    return frame_len;
}

pub fn parseSegment(frame: []const u8) ?Segment {
    if (frame.len < ethernet.header_len + ipv4.header_len + header_len) return null;

    if (readU16Be(frame, 12) != ethernet.ethertype_ipv4) return null;

    const ip_off = ethernet.header_len;
    if (frame[ip_off + 9] != ipv4.proto_tcp) return null;

    const ip_total = readU16Be(frame, ip_off + 2);
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

    var src_ip: ipv4.Addr = undefined;
    var dst_ip: ipv4.Addr = undefined;
    @memcpy(&src_ip, frame[ip_off + 12 ..][0..ipv4.addr_len]);
    @memcpy(&dst_ip, frame[ip_off + 16 ..][0..ipv4.addr_len]);

    return .{
        .src_ip = src_ip,
        .dst_ip = dst_ip,
        .src_port = readU16Be(frame, tcp_off),
        .dst_port = readU16Be(frame, tcp_off + 2),
        .seq = readU32Be(frame, tcp_off + 4),
        .ack = readU32Be(frame, tcp_off + 8),
        .flags = frame[tcp_off + 13],
        .payload = frame[payload_off .. payload_off + payload_len],
    };
}

fn readU16Be(buf: []const u8, off: usize) u16 {
    return (@as(u16, buf[off]) << 8) | @as(u16, buf[off + 1]);
}

fn readU32Be(buf: []const u8, off: usize) u32 {
    return (@as(u32, buf[off]) << 24) |
        (@as(u32, buf[off + 1]) << 16) |
        (@as(u32, buf[off + 2]) << 8) |
        @as(u32, buf[off + 3]);
}

fn writeU16Be(buf: []u8, off: usize, value: u16) void {
    buf[off] = @truncate(value >> 8);
    buf[off + 1] = @truncate(value);
}

fn writeU32Be(buf: []u8, off: usize, value: u32) void {
    buf[off] = @truncate(value >> 24);
    buf[off + 1] = @truncate(value >> 16);
    buf[off + 2] = @truncate(value >> 8);
    buf[off + 3] = @truncate(value);
}

pub fn matchEndpoint(
    frame: []const u8,
    local_port: u16,
    remote_ip: ipv4.Addr,
    remote_port: u16,
) ?Segment {
    const seg = parseSegment(frame) orelse return null;
    if (seg.dst_port != local_port) return null;
    if (!ipv4.equal(seg.src_ip, remote_ip)) return null;
    if (seg.src_port != remote_port) return null;
    return seg;
}
