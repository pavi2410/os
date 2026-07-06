const std = @import("std");
const dns_codec = @import("dns_codec");

test "buildQuery encodes example.com A query" {
    var query: [256]u8 = undefined;
    const len = try dns_codec.buildQuery("example.com", &query);

    try std.testing.expectEqual(@as(u8, 0x01), query[2]);
    try std.testing.expectEqual(@as(u8, 0x01), query[5]);
    try std.testing.expect(query[12] == 7);
    try std.testing.expectEqualStrings("example", query[13..20]);
    try std.testing.expect(query[20] == 3);
    try std.testing.expectEqualStrings("com", query[21..24]);
    try std.testing.expect(query[24] == 0);
    try std.testing.expectEqual(@as(u8, 0x00), query[len - 4]);
    try std.testing.expectEqual(@as(u8, 0x01), query[len - 3]);
}

test "encodeName rejects empty and leading dot" {
    var out: [64]u8 = undefined;
    try std.testing.expectError(error.BadName, dns_codec.encodeName("", &out));
    try std.testing.expectError(error.BadName, dns_codec.encodeName(".example.com", &out));
}

test "parseFirstA extracts first A record" {
    // Header + question + one A answer with compressed name pointer.
    const reply = [_]u8{
        0x12, 0x34, 0x81, 0x80, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
        7,    'e',  'x',  'a',  'm',  'p',  'l',  'e',  3,    'c',  'o',  'm',  0,
        0x00, 0x01, 0x00, 0x01,
        0xC0, 0x0C, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x3C, 0x00, 0x04,
        104,  20,   23,   154,
    };

    var ip: [4]u8 = undefined;
    try std.testing.expect(dns_codec.parseFirstA(&reply, &ip));
    try std.testing.expectEqual(@as(u8, 104), ip[0]);
    try std.testing.expectEqual(@as(u8, 154), ip[3]);
}

test "parseFirstA rejects truncated packets" {
    var ip: [4]u8 = undefined;
    try std.testing.expect(!dns_codec.parseFirstA(&.{ 0, 0, 0x81, 0x80, 0, 1, 0, 0 }, &ip));
}
