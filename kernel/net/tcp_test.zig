const std = @import("std");
const ethernet = @import("ethernet.zig");
const ipv4 = @import("ipv4.zig");
const ip_addr = @import("common/ipv4_addr");
const mac = @import("common/mac");
const tcp = @import("tcp.zig");

test "parseSegment reads SYN-ACK with MSS option" {
    var frame: [128]u8 = undefined;
    @memset(&frame, 0);

    ethernet.putHeader(&frame, mac.Mac.zero, mac.Mac.zero, ethernet.Ethertype.ipv4);
    ipv4.putHeader(
        frame[ethernet.header_len..],
        ip_addr.Addr.init(10, 0, 2, 2),
        ip_addr.Addr.init(10, 0, 2, 15),
        ipv4.Protocol.tcp,
        24,
    );

    const tcp_off = ethernet.header_len + ipv4.header_len;
    frame[tcp_off + 0] = 0xC0;
    frame[tcp_off + 1] = 0x00;
    frame[tcp_off + 2] = 0x00;
    frame[tcp_off + 3] = 0x50;
    frame[tcp_off + 4] = 0x00;
    frame[tcp_off + 5] = 0x00;
    frame[tcp_off + 6] = 0x00;
    frame[tcp_off + 7] = 0x01;
    frame[tcp_off + 8] = 0x12;
    frame[tcp_off + 9] = 0x34;
    frame[tcp_off + 10] = 0x56;
    frame[tcp_off + 11] = 0x78;
    frame[tcp_off + 12] = 0x60;
    frame[tcp_off + 13] = tcp.flag_syn | tcp.flag_ack;
    frame[tcp_off + 20] = 0x02;
    frame[tcp_off + 21] = 0x04;
    frame[tcp_off + 22] = 0x05;
    frame[tcp_off + 23] = 0xB4;

    const seg = tcp.parseSegment(&frame) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(u16, 80), seg.dst_port);
    try std.testing.expect(seg.flags & tcp.flag_syn != 0);
    try std.testing.expect(seg.flags & tcp.flag_ack != 0);
    try std.testing.expectEqual(@as(usize, 0), seg.payload.len);
}
