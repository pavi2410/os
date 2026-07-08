const std = @import("std");
const hex = @import("common/hex");

test "format colon hex" {
    var buf: [17]u8 = undefined;
    const bytes = [_]u8{ 0x52, 0x54, 0x00, 0x12, 0x34, 0x56 };
    try std.testing.expectEqualStrings("52:54:00:12:34:56", hex.formatColonHex(&bytes, &buf).?);
}

test "nibble helpers" {
    try std.testing.expectEqual(@as(u8, 'a'), hex.nibbleToHexLower(0xA));
    try std.testing.expectEqual(@as(u8, 0x5), hex.hexCharToNibble('5'));
    try std.testing.expectEqual(@as(u8, 0xF), hex.hexCharToNibble('f'));
}
