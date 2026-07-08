const std = @import("std");
const environ = @import("environ");

test "getenv finds exported variable" {
    const foo_env: *const [7:0]u8 = "FOO=bar";
    // argc=0 → argv[0]=null, envp starts at argv[1].
    var slots: [3]?[*:0]u8 = .{ null, @constCast(foo_env), null };

    const value = environ.getenv("FOO", 0, @ptrCast(&slots));
    try std.testing.expectEqualStrings("bar", value.?);
}

test "getenv returns null for missing variable" {
    // argc=0 → argv[0]=null, empty envp at argv[1]=null.
    var slots: [2]?[*:0]u8 = .{ null, null };

    try std.testing.expect(environ.getenv("MISSING", 0, @ptrCast(&slots)) == null);
}
