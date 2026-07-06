const std = @import("std");
const ethernet = @import("ethernet.zig");
const icmp = @import("icmp.zig");
const ipv4 = @import("ipv4.zig");

test "matchEchoReply rejects inflated IP total length" {
    var frame: [80]u8 = undefined;
    @memset(&frame, 0);

    ethernet.putHeader(&frame, .{0} ** 6, .{0} ** 6, ethernet.ethertype_ipv4);
    ipv4.putHeader(frame[ethernet.header_len..], .{ 10, 0, 2, 2 }, .{ 10, 0, 2, 15 }, ipv4.proto_icmp, 1500);

    const icmp_off = ethernet.header_len + ipv4.header_len;
    const hdr: *icmp.Header = @ptrCast(@alignCast(frame[icmp_off..].ptr));
    hdr.type = icmp.echo_reply;
    hdr.code = 0;
    hdr.identifier_be = @byteSwap(@as(u16, 0x4000));
    hdr.sequence_be = @byteSwap(@as(u16, 0));

    var src: ipv4.Addr = undefined;
    try std.testing.expect(icmp.matchEchoReply(&frame, 0x4000, 0, &src) == null);
}
