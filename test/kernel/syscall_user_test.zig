const std = @import("std");
const user = @import("syscall_user");

test "cString reads null-terminated user text within cap" {
    var text = [_]u8{ 'o', 's', 0 };
    const got = user.cString(@intFromPtr(&text), 8).?;
    try std.testing.expectEqualStrings("os", got);
}

test "cString rejects null and unterminated text" {
    try std.testing.expect(user.cString(0, 8) == null);

    var text = [_]u8{ 'o', 's' };
    try std.testing.expect(user.cString(@intFromPtr(&text), text.len) == null);
}

test "user range rejects null and overflow" {
    try std.testing.expect(!user.range(0, 1));
    try std.testing.expect(!user.range(std.math.maxInt(u64), 1));
}

test "readArgv reads bounded cstring vector" {
    var arg0 = [_]u8{ 'e', 'c', 'h', 'o', 0 };
    var arg1 = [_]u8{ 'h', 'i', 0 };
    var argv = [_]u64{
        @intFromPtr(&arg0),
        @intFromPtr(&arg1),
        0,
    };
    var out: [4][]const u8 = undefined;

    const count = try user.readArgv(@intFromPtr(&argv), &out, 16);
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqualStrings("echo", out[0]);
    try std.testing.expectEqualStrings("hi", out[1]);
}
