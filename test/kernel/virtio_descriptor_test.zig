const std = @import("std");
const descriptor = @import("virtio_descriptor");

test "descriptor flags encode next and writable bits" {
    try std.testing.expectEqual(@as(u16, 0), descriptor.descriptorFlags(false, false));
    try std.testing.expectEqual(descriptor.flags.next, descriptor.descriptorFlags(true, false));
    try std.testing.expectEqual(descriptor.flags.write, descriptor.descriptorFlags(false, true));
    try std.testing.expectEqual(
        descriptor.flags.next | descriptor.flags.write,
        descriptor.descriptorFlags(true, true),
    );
}

test "segment records physical buffer and device write direction" {
    const seg: descriptor.Segment = .{
        .phys = 0x1000,
        .len = 512,
        .writable = true,
    };
    try std.testing.expectEqual(@as(u64, 0x1000), seg.phys);
    try std.testing.expectEqual(@as(u32, 512), seg.len);
    try std.testing.expect(seg.writable);
}
