const std = @import("std");
const line = @import("line");

test "stripComment removes trailing hash comment" {
    var buf: [32]u8 = undefined;
    const input = "echo hello # ignored";
    @memcpy(buf[0..input.len], input);
    const len = line.stripComment(&buf, input.len);
    try std.testing.expectEqual(@as(usize, 10), len);
    try std.testing.expectEqualStrings("echo hello", buf[0..len]);
}

test "stripComment keeps hash inside double quotes" {
    var buf: [32]u8 = undefined;
    const input = "echo \"a#b\" rest";
    @memcpy(buf[0..input.len], input);
    const len = line.stripComment(&buf, input.len);
    try std.testing.expectEqual(@as(usize, input.len), len);
}

test "segmentCount splits on unquoted semicolon" {
    const input = "echo a; echo b";
    try std.testing.expectEqual(@as(usize, 2), line.segmentCount(input, input.len));
}

test "segmentCount keeps semicolon inside quotes" {
    const input = "echo \"a;b\"";
    try std.testing.expectEqual(@as(usize, 1), line.segmentCount(input, input.len));
}

test "chainPartCount splits on && and ||" {
    try std.testing.expectEqual(@as(usize, 3), line.chainPartCount("false && echo a || echo b"));
    try std.testing.expectEqual(@as(usize, 1), line.chainPartCount("echo only"));
}
