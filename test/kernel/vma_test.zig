const std = @import("std");
const vma = @import("vma");

test "insert find and overlap" {
    var table = vma.VmaTable.init();
    try table.insert(.{
        .base = 0x400000,
        .len = 0x1000,
        .prot = vma.PROT_READ | vma.PROT_EXEC,
        .flags = vma.MAP_PRIVATE,
        .kind = .elf,
    });
    try std.testing.expect(table.find(0x400000) != null);
    try std.testing.expect(table.find(0x400fff) != null);
    try std.testing.expect(table.find(0x401000) == null);
    try std.testing.expectError(vma.VmaError.Overlap, table.insert(.{
        .base = 0x400000,
        .len = 0x2000,
        .prot = vma.PROT_READ,
        .flags = vma.MAP_PRIVATE,
        .kind = .anon,
    }));
}

test "unmapRange punches hole" {
    var table = vma.VmaTable.init();
    try table.insert(.{
        .base = 0x10000,
        .len = 0x3000,
        .prot = vma.PROT_READ | vma.PROT_WRITE,
        .flags = vma.MAP_PRIVATE | vma.MAP_ANONYMOUS,
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
        .prot = vma.PROT_READ | vma.PROT_WRITE,
        .flags = vma.MAP_PRIVATE | vma.MAP_ANONYMOUS,
        .kind = .anon,
    });
    try table.setProt(0x21000, 0x1000, vma.PROT_READ);
    try std.testing.expectEqual(@as(usize, 3), table.count());
    const mid = table.find(0x21000).?;
    try std.testing.expectEqual(vma.PROT_READ, mid.prot);
    try std.testing.expectEqual(vma.PROT_READ | vma.PROT_WRITE, table.find(0x20000).?.prot);
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
    try std.testing.expect(vma.violatesWx(vma.PROT_WRITE | vma.PROT_EXEC));
    try std.testing.expect(!vma.violatesWx(vma.PROT_READ | vma.PROT_WRITE));
    try std.testing.expect(!vma.violatesWx(vma.PROT_READ | vma.PROT_EXEC));
}
