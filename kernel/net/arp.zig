const ethernet = @import("ethernet.zig");

pub const ipv4_len = 4;
pub const hardware_ethernet: u16 = 1;
pub const protocol_ipv4: u16 = 0x0800;
pub const op_request: u16 = 1;
pub const op_reply: u16 = 2;

pub const header_len = 28;

pub const Header = extern struct {
    hw_type_be: u16,
    proto_type_be: u16,
    hw_len: u8,
    proto_len: u8,
    opcode_be: u16,
    sender_mac: ethernet.Mac,
    sender_ip: [ipv4_len]u8,
    target_mac: ethernet.Mac,
    target_ip: [ipv4_len]u8,
};

pub fn opcodeHost(hdr: *const Header) u16 {
    return @byteSwap(hdr.opcode_be);
}

pub fn buildRequest(
    out: []u8,
    src_mac: ethernet.Mac,
    sender_ip: [ipv4_len]u8,
    target_ip: [ipv4_len]u8,
) usize {
    const frame_len = ethernet.min_frame_len;
    @memset(out[0..frame_len], 0);

    ethernet.putHeader(out, ethernet.broadcast, src_mac, ethernet.ethertype_arp);

    const arp: *Header = @ptrCast(@alignCast(out[ethernet.header_len..].ptr));
    arp.hw_type_be = @byteSwap(hardware_ethernet);
    arp.proto_type_be = @byteSwap(protocol_ipv4);
    arp.hw_len = ethernet.mac_len;
    arp.proto_len = ipv4_len;
    arp.opcode_be = @byteSwap(op_request);
    @memcpy(&arp.sender_mac, &src_mac);
    @memcpy(&arp.sender_ip, &sender_ip);
    @memcpy(&arp.target_ip, &target_ip);

    return frame_len;
}

pub fn isReply(frame: []const u8) bool {
    if (frame.len < ethernet.header_len + @sizeOf(Header)) return false;
    const eth: *const ethernet.Header = @ptrCast(@alignCast(frame.ptr));
    if (ethernet.ethertypeHost(eth) != ethernet.ethertype_arp) return false;
    const arp_hdr: *const Header = @ptrCast(@alignCast(frame[ethernet.header_len..].ptr));
    return opcodeHost(arp_hdr) == op_reply;
}

/// ARP reply for @p ip: returns the sender hardware address (resolved MAC).
pub fn senderMacFor(frame: []const u8, ip: [ipv4_len]u8) ?ethernet.Mac {
    if (!isReply(frame)) return null;
    const arp_hdr: *const Header = @ptrCast(@alignCast(frame[ethernet.header_len..].ptr));
    if (!ipEqual(arp_hdr.sender_ip, ip)) return null;
    return arp_hdr.sender_mac;
}

fn ipEqual(a: [ipv4_len]u8, b: [ipv4_len]u8) bool {
    return @as(u32, @bitCast(a)) == @as(u32, @bitCast(b));
}
