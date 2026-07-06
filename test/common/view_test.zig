const std = @import("std");
const view = @import("common_view");

const Sample = extern struct {
    a: u32,
    b: u16,
};

test "view get and mut honor bounds and alignment" {
    var buf: [8]u8 = undefined;
    const hdr = view.mut(Sample, &buf, 0).?;
    hdr.a = 0x12345678;
    hdr.b = 0xABCD;

    const got = view.get(Sample, &buf, 0).?;
    try std.testing.expectEqual(@as(u32, 0x12345678), got.a);
    try std.testing.expectEqual(@as(u16, 0xABCD), got.b);

    try std.testing.expect(view.get(Sample, &buf, 1) == null);
    try std.testing.expect(view.mut(Sample, &buf, 5) == null);
}
