const std = @import("std");
const expand = @import("expand");

fn mockLookup(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "PATH")) return "/BIN";
    if (std.mem.eql(u8, name, "FOO")) return "bar";
    return null;
}

test "expand replaces a single variable" {
    var out: [64]u8 = undefined;
    const result = expand.expandWith("$PATH", &out, mockLookup).?;
    try std.testing.expectEqualStrings("/BIN", result);
}

test "expand replaces variable inside text" {
    var out: [64]u8 = undefined;
    const result = expand.expandWith("prefix$PATH", &out, mockLookup).?;
    try std.testing.expectEqualStrings("prefix/BIN", result);
}

test "expand leaves unknown variables empty" {
    var out: [64]u8 = undefined;
    const result = expand.expandWith("x$MISSING", &out, mockLookup).?;
    try std.testing.expectEqualStrings("x", result);
}

test "expand keeps a bare dollar sign" {
    var out: [64]u8 = undefined;
    const result = expand.expandWith("cost is $", &out, mockLookup).?;
    try std.testing.expectEqualStrings("cost is $", result);
}

test "expand handles multiple variables" {
    var out: [64]u8 = undefined;
    const result = expand.expandWith("$FOO:$PATH", &out, mockLookup).?;
    try std.testing.expectEqualStrings("bar:/BIN", result);
}

test "expandArgv expands each parsed token" {
    const argv = @import("argv");

    var parsed: argv.Parsed = .{};
    parsed.argc = 2;
    parsed.args[0] = "ls";
    parsed.args[1] = "$PATH";
    var storage: [argv.max_args][expand.max_arg_len]u8 = undefined;
    try std.testing.expect(expand.expandArgvWith(&parsed, &storage, mockLookup));
    try std.testing.expectEqualStrings("ls", parsed.args[0]);
    try std.testing.expectEqualStrings("/BIN", parsed.args[1]);
}
