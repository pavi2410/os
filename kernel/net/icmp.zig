const ethernet = @import("ethernet.zig");
const ipv4 = @import("ipv4.zig");

pub const header_len = 8;
pub const echo_request: u8 = 8;
pub const echo_reply: u8 = 0;

pub const echo_payload_len = 32;

pub const Header = extern struct {
    type: u8,
    code: u8,
    checksum_be: u16,
    identifier_be: u16,
    sequence_be: u16,
};

pub fn identifierHost(hdr: *const Header) u16 {
    return @byteSwap(hdr.identifier_be);
}

pub fn sequenceHost(hdr: *const Header) u16 {
    return @byteSwap(hdr.sequence_be);
}

pub fn buildEchoRequest(
    out: []u8,
    dst_mac: ethernet.Mac,
    src_mac: ethernet.Mac,
    src_ip: ipv4.Addr,
    dst_ip: ipv4.Addr,
    id: u16,
    sequence: u16,
) usize {
    const icmp_len: u16 = header_len + echo_payload_len;
    const ip_len = ipv4.header_len + icmp_len;
    var frame_len: usize = ethernet.header_len + ip_len;
    if (frame_len < ethernet.min_frame_len) frame_len = ethernet.min_frame_len;
    @memset(out[0..frame_len], 0);

    ethernet.putHeader(out, dst_mac, src_mac, ethernet.ethertype_ipv4);
    ipv4.putHeader(out[ethernet.header_len..], src_ip, dst_ip, ipv4.proto_icmp, icmp_len);

    const icmp_off = ethernet.header_len + ipv4.header_len;
    const icmp: *Header = @ptrCast(@alignCast(out[icmp_off..].ptr));
    icmp.type = echo_request;
    icmp.code = 0;
    icmp.checksum_be = 0;
    icmp.identifier_be = @byteSwap(id);
    icmp.sequence_be = @byteSwap(sequence);

    var i: usize = 0;
    while (i < echo_payload_len) : (i += 1) {
        out[icmp_off + header_len + i] = @truncate(i);
    }

    const csum = ipv4.internetChecksum(out[icmp_off .. icmp_off + icmp_len]);
    icmp.checksum_be = @byteSwap(csum);

    return frame_len;
}

/// Echo reply for @p id (and optional @p sequence). Returns ICMP payload bytes.
pub fn matchEchoReply(
    frame: []const u8,
    id: u16,
    sequence: ?u16,
    src_ip_out: *ipv4.Addr,
) ?[]const u8 {
    if (frame.len < ethernet.header_len + ipv4.header_len + header_len) return null;

    const eth: *const ethernet.Header = @ptrCast(@alignCast(frame.ptr));
    if (ethernet.ethertypeHost(eth) != ethernet.ethertype_ipv4) return null;

    const ip: *const ipv4.Header = @ptrCast(@alignCast(frame[ethernet.header_len..].ptr));
    if (ip.protocol != ipv4.proto_icmp) return null;

    const ip_total = ipv4.totalLengthHost(ip);
    if (ip_total < ipv4.header_len + header_len) return null;

    const icmp_off = ethernet.header_len + ipv4.header_len;
    const icmp: *const Header = @ptrCast(@alignCast(frame[icmp_off..].ptr));
    if (icmp.type != echo_reply) return null;
    if (icmp.code != 0) return null;
    if (identifierHost(icmp) != id) return null;
    if (sequence) |seq| {
        if (sequenceHost(icmp) != seq) return null;
    }

    const icmp_len = ip_total - ipv4.header_len;
    const payload_off = icmp_off + header_len;
    const frame_ip_end = ethernet.header_len + ip_total;
    if (payload_off > frame_ip_end or icmp_len < header_len) return null;

    src_ip_out.* = ip.src;
    return frame[payload_off..frame_ip_end];
}

pub fn isEchoReply(
    frame: []const u8,
    expected_src: ipv4.Addr,
    id: u16,
    sequence: u16,
) bool {
    var src: ipv4.Addr = undefined;
    if (matchEchoReply(frame, id, sequence, &src)) |_| {
        return ipv4.equal(src, expected_src);
    }
    return false;
}
