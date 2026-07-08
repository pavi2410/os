const view = @import("common/view");
const ethernet = @import("ethernet.zig");
const ipv4 = @import("ipv4.zig");
const ipv4_addr = @import("common/ipv4_addr");
const mac = @import("common/mac");

pub const HardwareType = enum(u16) {
    ethernet = 1,
};

pub const Opcode = enum(u16) {
    request = 1,
    reply = 2,

    pub inline fn fromHost(host: u16) ?Opcode {
        return switch (host) {
            @intFromEnum(Opcode.request) => .request,
            @intFromEnum(Opcode.reply) => .reply,
            else => null,
        };
    }
};

comptime {
    if (@intFromEnum(HardwareType.ethernet) != 1) @compileError("HardwareType.ethernet must be 1");
    if (@intFromEnum(Opcode.request) != 1) @compileError("Opcode.request must be 1");
    if (@intFromEnum(Opcode.reply) != 2) @compileError("Opcode.reply must be 2");
}

pub const header_len = 28;

pub const Header = extern struct {
    hw_type_be: u16,
    proto_type_be: u16,
    hw_len: u8,
    proto_len: u8,
    opcode_be: u16,
    sender_mac: mac.Mac,
    sender_ip: ipv4_addr.Addr,
    target_mac: mac.Mac,
    target_ip: ipv4_addr.Addr,
};

pub fn opcodeHost(hdr: *const Header) u16 {
    return @byteSwap(hdr.opcode_be);
}

pub fn headerOpcode(hdr: *const Header) ?Opcode {
    return Opcode.fromHost(opcodeHost(hdr));
}

pub fn buildRequest(
    out: []u8,
    src_mac: mac.Mac,
    sender_ip: ipv4_addr.Addr,
    target_ip: ipv4_addr.Addr,
) usize {
    const frame_len = ethernet.min_frame_len;
    @memset(out[0..frame_len], 0);

    ethernet.putHeader(out, mac.Mac.broadcast, src_mac, ethernet.Ethertype.arp);

    const arp = view.mut(Header, out, ethernet.header_len).?;
    arp.hw_type_be = @byteSwap(@intFromEnum(HardwareType.ethernet));
    arp.proto_type_be = ethernet.Ethertype.ipv4.toBe();
    arp.hw_len = mac.len;
    arp.proto_len = ipv4_addr.len;
    arp.opcode_be = @byteSwap(@intFromEnum(Opcode.request));
    arp.sender_mac = src_mac;
    arp.sender_ip = sender_ip;
    arp.target_ip = target_ip;

    return frame_len;
}

pub fn isReply(frame: []const u8) bool {
    if (frame.len < ethernet.header_len + @sizeOf(Header)) return false;
    const eth = view.get(ethernet.Header, frame, 0) orelse return false;
    if (ethernet.headerEthertype(eth) != .arp) return false;
    const arp_hdr = view.get(Header, frame, ethernet.header_len) orelse return false;
    return headerOpcode(arp_hdr) == .reply;
}

/// ARP reply for @p ip: returns the sender hardware address (resolved MAC).
pub fn senderMacFor(frame: []const u8, addr: ipv4_addr.Addr) ?mac.Mac {
    if (!isReply(frame)) return null;
    const arp_hdr = view.get(Header, frame, ethernet.header_len) orelse return null;
    if (!arp_hdr.sender_ip.eql(addr)) return null;
    return arp_hdr.sender_mac;
}
