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

test "stripComment treats whole line comment as empty" {
    var buf: [16]u8 = undefined;
    const input = "# hello";
    @memcpy(buf[0..input.len], input);
    const len = line.stripComment(&buf, input.len);
    try std.testing.expectEqual(@as(usize, 0), len);
}
