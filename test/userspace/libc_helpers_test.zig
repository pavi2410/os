const std = @import("std");
const ip = @import("libc_ip");
const format = @import("libc_format");

test "IPv4 parser accepts valid dotted decimal" {
    var addr: [4]u8 = undefined;
    try std.testing.expect(ip.parseIpv4("104.20.23.154", &addr));
    try std.testing.expectEqualSlices(u8, &.{ 104, 20, 23, 154 }, &addr);
}

test "IPv4 parser rejects malformed octets" {
    var addr: [4]u8 = undefined;
    try std.testing.expect(!ip.parseIpv4("", &addr));
    try std.testing.expect(!ip.parseIpv4("10..2.2", &addr));
    try std.testing.expect(!ip.parseIpv4("10.0.2", &addr));
    try std.testing.expect(!ip.parseIpv4("10.0.2.256", &addr));
    try std.testing.expect(!ip.parseIpv4("10.0.2.2.", &addr));
}

test "IPv4 and MAC formatters produce CLI strings" {
    var ip_buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("10.0.2.2", ip.formatIpv4(.{ 10, 0, 2, 2 }, &ip_buf).?);

    var mac_buf: [18]u8 = undefined;
    try std.testing.expectEqualStrings("52:54:00:12:34:56", ip.formatMac(.{ 0x52, 0x54, 0x00, 0x12, 0x34, 0x56 }, &mac_buf).?);
}

test "network mask helpers match ip command output" {
    try std.testing.expectEqual(@as(u8, 24), ip.maskPrefix(.{ 255, 255, 255, 0 }));
    try std.testing.expectEqualSlices(u8, &.{ 10, 0, 2, 0 }, &ip.networkAddr(.{ 10, 0, 2, 15 }, .{ 255, 255, 255, 0 }));
}

test "decimal formatter handles zero and large values" {
    var buf: [20]u8 = undefined;
    try std.testing.expectEqualStrings("0", format.decimal(0, &buf).?);
    try std.testing.expectEqualStrings("123456", format.decimal(123456, &buf).?);
}
