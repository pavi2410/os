const std = @import("std");
const path = @import("common/path");

test "root and from" {
    const P = path.Path(32);
    const root = P.root();
    try std.testing.expect(root.eql("/"));

    const bin = P.from("/BIN");
    try std.testing.expect(bin.eql("/BIN"));
}

test "resolve relative against cwd" {
    var out: [64]u8 = undefined;
    const resolved = try path.resolveAgainst("/TDIR", "NOTE.TXT", &out);
    try std.testing.expectEqualStrings("/TDIR/NOTE.TXT", resolved);
}

test "resolve dotdot" {
    var out: [64]u8 = undefined;
    const resolved = try path.resolveAgainst("/TDIR/SUB", "..", &out);
    try std.testing.expectEqualStrings("/TDIR", resolved);
}

test "join" {
    var out: [64]u8 = undefined;
    const joined = try path.join("/BIN", "SHELL", &out);
    try std.testing.expectEqualStrings("/BIN/SHELL", joined);
}

test "resolveFrom on Path" {
    const P = path.Path(64);
    var base = P.from("/TDIR");
    var out = P.empty();
    try base.resolveFrom("SUB/FILE.TXT", &out);
    try std.testing.expect(out.eql("/TDIR/SUB/FILE.TXT"));
}
