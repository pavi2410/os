const std = @import("std");
const mac_mod = @import("common_mac");

test "Mac comptime constructors and formatting" {
    const mac = mac_mod.Mac.parse("52:54:00:12:34:56");
    try std.testing.expect(mac.eql(mac_mod.Mac.init(0x52, 0x54, 0x00, 0x12, 0x34, 0x56)));
    try std.testing.expect(mac.eql(mac_mod.Mac.parse("525400123456")));

    var buf: [mac_mod.Mac.format_len]u8 = undefined;
    try std.testing.expectEqualStrings("52:54:00:12:34:56", mac.formatBuf(&buf).?);
    try std.testing.expectEqualStrings("52:54:00:12:34:56", try std.fmt.bufPrint(&buf, "{f}", .{mac}));
}

test "Mac broadcast and equality" {
    try std.testing.expect(mac_mod.Mac.broadcast.isBroadcast());
}
