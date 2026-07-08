const std = @import("std");
const ip = @import("common_ipv4_addr");

test "Addr parse and format" {
    const addr = ip.Addr.parse("10.0.2.15");
    try std.testing.expect(addr.eql(ip.Addr.init(10, 0, 2, 15)));

    var buf: [ip.Addr.format_len]u8 = undefined;
    try std.testing.expectEqualStrings("10.0.2.15", addr.formatBuf(&buf).?);
    try std.testing.expectEqualStrings("10.0.2.15", try std.fmt.bufPrint(&buf, "{f}", .{addr}));
}

test "Addr runtime parse rejects invalid input" {
    try std.testing.expect(ip.Addr.parseText("104.20.23.154") != null);
    try std.testing.expect(ip.Addr.parseText("") == null);
    try std.testing.expect(ip.Addr.parseText("10..2.2") == null);
    try std.testing.expect(ip.Addr.parseText("10.0.2") == null);
    try std.testing.expect(ip.Addr.parseText("10.0.2.256") == null);
    try std.testing.expect(ip.Addr.parseText("10.0.2.2.") == null);
}

test "Addr subnet helpers" {
    const guest = ip.Addr.parse("10.0.2.15");
    const mask = ip.Addr.parse("255.255.255.0");
    try std.testing.expect(guest.sameSubnet(ip.Addr.parse("10.0.2.3"), mask));
    try std.testing.expectEqual(@as(u8, 24), ip.Addr.prefixBits(mask));
}
