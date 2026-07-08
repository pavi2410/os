const std = @import("std");
const string = @import("common/string");

test "from literal" {
    const S = string.String(16);
    const s = S.from("/BIN");
    try std.testing.expect(s.eql("/BIN"));
}

test "set and slice" {
    const S = string.String(16);
    var s = S.empty();
    try s.set("/");
    try std.testing.expect(s.eql("/"));
    try s.set("/BIN");
    try std.testing.expect(s.eql("/BIN"));
}

test "setLen after external write" {
    const S = string.String(8);
    var s = S.empty();
    @memcpy(s.bufPtr()[0..3], "foo");
    try s.setLen(3);
    try std.testing.expect(s.eql("foo"));
}

test "too long rejected" {
    const S = string.String(4);
    var s = S.empty();
    try std.testing.expectError(S.Error.TooLong, s.set("abcd"));
}
