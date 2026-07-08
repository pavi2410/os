const view = @import("common_view");
const ethernet = @import("ethernet.zig");
const ipv4 = @import("ipv4.zig");
const mac = @import("common_mac");

pub const hardware_ethernet: u16 = 1;
pub const op_request: u16 = 1;
pub const op_reply: u16 = 2;

pub const header_len = 28;

pub const Header = extern struct {
    hw_type_be: u16,
    proto_type_be: u16,
    hw_len: u8,
    proto_len: u8,
    opcode_be: u16,
    sender_mac: mac.Mac,
    sender_ip: ipv4.Addr,
    target_mac: mac.Mac,
    target_ip: ipv4.Addr,
};

pub fn opcodeHost(hdr: *const Header) u16 {
    return @byteSwap(hdr.opcode_be);
}

pub fn buildRequest(
    out: []u8,
    src_mac: mac.Mac,
    sender_ip: ipv4.Addr,
    target_ip: ipv4.Addr,
) usize {
    const frame_len = ethernet.min_frame_len;
    @memset(out[0..frame_len], 0);

    ethernet.putHeader(out, mac.Mac.broadcast, src_mac, ethernet.Ethertype.arp);

    const arp = view.mut(Header, out, ethernet.header_len).?;
    arp.hw_type_be = @byteSwap(hardware_ethernet);
    arp.proto_type_be = ethernet.Ethertype.ipv4.toBe();
    arp.hw_len = mac.len;
    arp.proto_len = ipv4.addr_len;
    arp.opcode_be = @byteSwap(op_request);
    arp.sender_mac = src_mac;
    @memcpy(&arp.sender_ip, &sender_ip);
    @memcpy(&arp.target_ip, &target_ip);

    return frame_len;
}

pub fn isReply(frame: []const u8) bool {
    if (frame.len < ethernet.header_len + @sizeOf(Header)) return false;
    const eth = view.get(ethernet.Header, frame, 0) orelse return false;
    if (ethernet.headerEthertype(eth) != .arp) return false;
    const arp_hdr = view.get(Header, frame, ethernet.header_len) orelse return false;
    return opcodeHost(arp_hdr) == op_reply;
}

/// ARP reply for @p ip: returns the sender hardware address (resolved MAC).
pub fn senderMacFor(frame: []const u8, ip: ipv4.Addr) ?mac.Mac {
    if (!isReply(frame)) return null;
    const arp_hdr = view.get(Header, frame, ethernet.header_len) orelse return null;
    if (!ipv4.equal(arp_hdr.sender_ip, ip)) return null;
    return arp_hdr.sender_mac;
}
