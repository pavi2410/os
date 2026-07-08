const view = @import("common_view");
const ethernet = @import("ethernet.zig");
const ipv4 = @import("ipv4.zig");
const mac = @import("common_mac");

pub const header_len = 8;

pub const Header = extern struct {
    src_port_be: u16,
    dst_port_be: u16,
    length_be: u16,
    checksum_be: u16,
};

pub fn srcPortHost(hdr: *const Header) u16 {
    return @byteSwap(hdr.src_port_be);
}

pub fn dstPortHost(hdr: *const Header) u16 {
    return @byteSwap(hdr.dst_port_be);
}

pub fn lengthHost(hdr: *const Header) u16 {
    return @byteSwap(hdr.length_be);
}

pub fn build(
    out: []u8,
    dst_mac: mac.Mac,
    src_mac: mac.Mac,
    src_ip: ipv4.Addr,
    dst_ip: ipv4.Addr,
    src_port: u16,
    dst_port: u16,
    payload: []const u8,
) usize {
    const udp_len: u16 = header_len + @as(u16, @intCast(payload.len));
    const ip_len = ipv4.header_len + udp_len;
    var frame_len: usize = ethernet.header_len + ip_len;
    if (frame_len < ethernet.min_frame_len) frame_len = ethernet.min_frame_len;
    @memset(out[0..frame_len], 0);

    ethernet.putHeader(out, dst_mac, src_mac, ethernet.Ethertype.ipv4);
    ipv4.putHeader(out[ethernet.header_len..], src_ip, dst_ip, ipv4.proto_udp, udp_len);

    const udp_off = ethernet.header_len + ipv4.header_len;
    const hdr = view.mut(Header, out, udp_off).?;
    hdr.src_port_be = @byteSwap(src_port);
    hdr.dst_port_be = @byteSwap(dst_port);
    hdr.length_be = @byteSwap(udp_len);
    hdr.checksum_be = 0;

    @memcpy(out[udp_off + header_len ..][0..payload.len], payload);
    return frame_len;
}

pub fn payloadSlice(frame: []const u8) ?[]const u8 {
    if (frame.len < ethernet.header_len + ipv4.header_len + header_len) return null;
    const eth = view.get(ethernet.Header, frame, 0) orelse return null;
    if (ethernet.headerEthertype(eth) != .ipv4) return null;

    const ip = view.get(ipv4.Header, frame, ethernet.header_len) orelse return null;
    if (ip.protocol != ipv4.proto_udp) return null;

    const ip_total = ipv4.totalLengthHost(ip);
    if (ip_total < ipv4.header_len + header_len) return null;

    const udp = view.get(Header, frame, ethernet.header_len + ipv4.header_len) orelse return null;
    const udp_total = lengthHost(udp);
    if (udp_total < header_len) return null;
    const payload_len = udp_total - header_len;

    const payload_off = ethernet.header_len + ipv4.header_len + header_len;
    if (frame.len < payload_off + payload_len) return null;
    return frame[payload_off .. payload_off + payload_len];
}

pub fn match(
    frame: []const u8,
    local_port: u16,
    src_ip_out: *ipv4.Addr,
    src_port_out: *u16,
) ?[]const u8 {
    const payload = payloadSlice(frame) orelse return null;
    const ip = view.get(ipv4.Header, frame, ethernet.header_len) orelse return null;
    const udp = view.get(Header, frame, ethernet.header_len + ipv4.header_len) orelse return null;
    if (dstPortHost(udp) != local_port) return null;
    src_ip_out.* = ip.src;
    src_port_out.* = srcPortHost(udp);
    return payload;
}
