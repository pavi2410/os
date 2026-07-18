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

test "simulateShortCircuit skips && rhs on failure" {
    var ran: [3]bool = undefined;
    const n = try line.simulateShortCircuit("false && echo no", &.{ 1, 0 }, ran[0..2]);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expect(ran[0]);
    try std.testing.expect(!ran[1]);
}

test "simulateShortCircuit runs || rhs on failure" {
    var ran: [2]bool = undefined;
    const n = try line.simulateShortCircuit("false || echo yes", &.{ 1, 0 }, &ran);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expect(ran[0]);
    try std.testing.expect(ran[1]);
}

test "simulateShortCircuit skips || rhs on success" {
    var ran: [2]bool = undefined;
    const n = try line.simulateShortCircuit("true || echo no", &.{ 0, 0 }, &ran);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expect(ran[0]);
    try std.testing.expect(!ran[1]);
}
