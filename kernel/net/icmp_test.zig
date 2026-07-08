const std = @import("std");
const view = @import("common/view");
const ethernet = @import("ethernet.zig");
const icmp = @import("icmp.zig");
const ipv4 = @import("ipv4.zig");
const ip_addr = @import("common/ipv4_addr");
const mac = @import("common/mac");

test "matchEchoReply rejects inflated IP total length" {
    var frame: [80]u8 = undefined;
    @memset(&frame, 0);

    ethernet.putHeader(&frame, mac.Mac.zero, mac.Mac.zero, ethernet.Ethertype.ipv4);
    ipv4.putHeader(
        frame[ethernet.header_len..],
        ip_addr.Addr.init(10, 0, 2, 2),
        ip_addr.Addr.init(10, 0, 2, 15),
        ipv4.Protocol.icmp,
        1500,
    );

    const icmp_off = ethernet.header_len + ipv4.header_len;
    const hdr = view.mut(icmp.Header, &frame, icmp_off).?;
    hdr.type = icmp.echo_reply;
    hdr.code = 0;
    hdr.identifier_be = @byteSwap(@as(u16, 0x4000));
    hdr.sequence_be = @byteSwap(@as(u16, 0));

    var src: ip_addr.Addr = undefined;
    try std.testing.expect(icmp.matchEchoReply(&frame, 0x4000, 0, &src) == null);
}
