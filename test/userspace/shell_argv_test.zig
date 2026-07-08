const std = @import("std");
const argv = @import("argv");

test "parse keeps spaces inside double quotes" {
    var line: [64]u8 = undefined;
    const input = "echo \"hello world\"";
    @memcpy(line[0..input.len], input);
    const parsed = try argv.parse(&line, input.len);
    try std.testing.expectEqual(@as(usize, 2), parsed.argc);
    try std.testing.expectEqualStrings("echo", parsed.args[0]);
    try std.testing.expectEqualStrings("hello world", parsed.args[1]);
}

test "parse supports escaped quote inside double quotes" {
    var line: [64]u8 = undefined;
    const input = "echo \"say \\\"hi\\\"\"";
    @memcpy(line[0..input.len], input);
    const parsed = try argv.parse(&line, input.len);
    try std.testing.expectEqualStrings("say \"hi\"", parsed.args[1]);
}

test "parse still splits unquoted tokens on spaces" {
    var line: [64]u8 = undefined;
    const input = "echo one two";
    @memcpy(line[0..input.len], input);
    const parsed = try argv.parse(&line, input.len);
    try std.testing.expectEqual(@as(usize, 3), parsed.argc);
    try std.testing.expectEqualStrings("two", parsed.args[2]);
}
