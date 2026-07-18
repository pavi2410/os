const std = @import("std");
const vma = @import("vma");

test "insert find and overlap" {
    var table = vma.VmaTable.init();
    try table.insert(.{
        .base = 0x400000,
        .len = 0x1000,
        .prot = .{ .read = true, .exec = true },
        .flags = .{ .private = true },
        .kind = .elf,
    });
    try std.testing.expect(table.find(0x400000) != null);
    try std.testing.expect(table.find(0x400fff) != null);
    try std.testing.expect(table.find(0x401000) == null);
    try std.testing.expectError(vma.VmaError.Overlap, table.insert(.{
        .base = 0x400000,
        .len = 0x2000,
        .prot = .{ .read = true },
        .flags = .{ .private = true },
        .kind = .anon,
    }));
}

test "unmapRange punches hole" {
    var table = vma.VmaTable.init();
    try table.insert(.{
        .base = 0x10000,
        .len = 0x3000,
        .prot = .{ .read = true, .write = true },
        .flags = .{ .private = true, .anonymous = true },
        .kind = .anon,
    });
    try table.unmapRange(0x11000, 0x1000);
    try std.testing.expectEqual(@as(usize, 2), table.count());
    try std.testing.expect(table.find(0x10000) != null);
    try std.testing.expect(table.find(0x11000) == null);
    try std.testing.expect(table.find(0x12000) != null);
}

test "setProt splits region" {
    var table = vma.VmaTable.init();
    try table.insert(.{
        .base = 0x20000,
        .len = 0x3000,
        .prot = .{ .read = true, .write = true },
        .flags = .{ .private = true, .anonymous = true },
        .kind = .anon,
    });
    try table.setProt(0x21000, 0x1000, .{ .read = true });
    try std.testing.expectEqual(@as(usize, 3), table.count());
    const mid = table.find(0x21000).?;
    try std.testing.expectEqual(vma.Prot{ .read = true }, mid.prot);
    try std.testing.expectEqual(vma.Prot{ .read = true, .write = true }, table.find(0x20000).?.prot);
}

test "setHeapEnd creates and grows" {
    var table = vma.VmaTable.init();
    try table.setHeapEnd(0x400000, 0x400000);
    try std.testing.expectEqual(@as(usize, 0), table.count());
    try table.setHeapEnd(0x400000, 0x402000);
    try std.testing.expectEqual(@as(usize, 1), table.count());
    try table.setHeapEnd(0x400000, 0x405000);
    try std.testing.expectEqual(@as(u64, 0x5000), table.find(0x400000).?.len);
}

test "violatesWx detects write-exec" {
    try std.testing.expect(vma.violatesWx(.{ .write = true, .exec = true }));
    try std.testing.expect(!vma.violatesWx(.{ .read = true, .write = true }));
    try std.testing.expect(!vma.violatesWx(.{ .read = true, .exec = true }));
}
