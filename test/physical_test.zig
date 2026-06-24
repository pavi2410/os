const std = @import("std");
const physical_bitmap = @import("physical_bitmap");

test "bitmap allocator returns aligned conventional pages" {
    var storage: [512]u8 = undefined;

    const regions = [_]physical_bitmap.Range{
        .{ .start = 0x1000, .end = 0x5000, .allocatable = true },
        .{ .start = 0x8000, .end = 0x9000, .allocatable = false },
    };

    var alloc = physical_bitmap.PageBitmap.initFromRegions(&storage, &regions);
    try std.testing.expectEqual(@as(usize, 4), alloc.total_allocatable);

    const page0 = alloc.allocPage().?;
    try std.testing.expect(page0 >= 0x1000 and page0 < 0x5000);
    try std.testing.expectEqual(@as(u64, 0), page0 % physical_bitmap.page_size);

    const page1 = alloc.allocPage().?;
    try std.testing.expect(page1 != page0);
    try std.testing.expectEqual(@as(usize, 2), alloc.free_pages);
}

test "bitmap allocator does not allocate reserved regions" {
    var storage: [512]u8 = undefined;

    const regions = [_]physical_bitmap.Range{
        .{ .start = 0x1000, .end = 0x2000, .allocatable = true },
        .{ .start = 0x2000, .end = 0x5000, .allocatable = false },
    };

    var alloc = physical_bitmap.PageBitmap.initFromRegions(&storage, &regions);
    try std.testing.expectEqual(@as(usize, 1), alloc.total_allocatable);

    const page = alloc.allocPage().?;
    try std.testing.expect(page < 0x3000);

    try std.testing.expect(alloc.allocPage() == null);
}

test "bitmap alloc and free maintain counters" {
    var storage: [512]u8 = undefined;

    const regions = [_]physical_bitmap.Range{
        .{ .start = 0x1000, .end = 0x9000, .allocatable = true },
    };

    var alloc = physical_bitmap.PageBitmap.initFromRegions(&storage, &regions);
    try std.testing.expectEqual(@as(usize, 8), alloc.total_allocatable);

    var pages: [8]u64 = undefined;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        pages[i] = alloc.allocPage().?;
    }
    try std.testing.expectEqual(@as(usize, 0), alloc.free_pages);
    try std.testing.expectEqual(@as(usize, 8), alloc.usedPages());

    i = 0;
    while (i < 8) : (i += 1) {
        try alloc.freePage(pages[i]);
    }

    try std.testing.expectEqual(@as(usize, 8), alloc.free_pages);
    try std.testing.expectEqual(@as(usize, 0), alloc.usedPages());
}

test "bitmap stress alloc and free cycles" {
    var storage: [4096]u8 = undefined;

    const regions = [_]physical_bitmap.Range{
        .{ .start = 0x100000, .end = 0x200000, .allocatable = true },
        .{ .start = 0x800000, .end = 0x801000, .allocatable = false },
    };

    var alloc = physical_bitmap.PageBitmap.initFromRegions(&storage, &regions);
    const initial_free = alloc.free_pages;

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const page = alloc.allocPage().?;
        try alloc.freePage(page);
    }

    try std.testing.expectEqual(initial_free, alloc.free_pages);
    try std.testing.expectEqual(@as(usize, 0), alloc.usedPages());
}

test "double free is rejected" {
    var storage: [512]u8 = undefined;

    const regions = [_]physical_bitmap.Range{
        .{ .start = 0x1000, .end = 0x3000, .allocatable = true },
    };

    var alloc = physical_bitmap.PageBitmap.initFromRegions(&storage, &regions);
    const page = alloc.allocPage().?;
    try alloc.freePage(page);
    try std.testing.expectError(error.DoubleFree, alloc.freePage(page));
}
