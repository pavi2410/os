const std = @import("std");
const seq = @import("seq");

test "readAt copies from offset and returns EOF" {
    const data = "hello world";
    var buf: [8]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 5), seq.readAt(data, 0, buf[0..5]));
    try std.testing.expectEqualStrings("hello", buf[0..5]);
    try std.testing.expectEqual(@as(usize, 5), seq.readAt(data, 6, buf[0..5]));
    try std.testing.expectEqualStrings("world", buf[0..5]);
    try std.testing.expectEqual(@as(usize, 0), seq.readAt(data, 11, &buf));
}

test "appendU64 and appendHex" {
    var buf: [32]u8 = undefined;
    var p = seq.appendU64(&buf, 0, 42);
    try std.testing.expectEqualStrings("42", buf[0..p]);
    p = seq.appendHex(&buf, 0, 0x1a2b, 4);
    try std.testing.expectEqualStrings("1a2b", buf[0..p]);
}
