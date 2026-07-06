const std = @import("std");
const bytes = @import("common_bytes");

test "big endian integer helpers" {
    var buf: [8]u8 = .{0} ** 8;
    bytes.writeU16Be(&buf, 1, 0x1234);
    bytes.writeU32Be(&buf, 3, 0x89AB_CDEF);

    try std.testing.expectEqual(@as(u16, 0x1234), bytes.readU16Be(&buf, 1));
    try std.testing.expectEqual(@as(u32, 0x89AB_CDEF), bytes.readU32Be(&buf, 3));
    try std.testing.expectEqual(@as(u8, 0x12), buf[1]);
    try std.testing.expectEqual(@as(u8, 0xEF), buf[6]);
}

test "little endian integer helpers" {
    var buf: [8]u8 = .{0} ** 8;
    bytes.writeU16Le(&buf, 1, 0x1234);
    bytes.writeU32Le(&buf, 3, 0x89AB_CDEF);

    try std.testing.expectEqual(@as(u16, 0x1234), bytes.readU16Le(&buf, 1));
    try std.testing.expectEqual(@as(u32, 0x89AB_CDEF), bytes.readU32Le(&buf, 3));
    try std.testing.expectEqual(@as(u8, 0x34), buf[1]);
    try std.testing.expectEqual(@as(u8, 0x89), buf[6]);
}
