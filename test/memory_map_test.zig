const std = @import("std");
const limine = @import("limine");
const memory_map = @import("memory_map");

test "parse Limine memory map entries" {
    var entry0 = limine.MemmapEntry{
        .base = 0x100000,
        .length = 0x10000,
        .type = @intFromEnum(limine.MemmapType.usable),
    };
    var entry1 = limine.MemmapEntry{
        .base = 0xFED00000,
        .length = 0x1000,
        .type = @intFromEnum(limine.MemmapType.framebuffer),
    };

    var entries: [2]?*limine.MemmapEntry = .{ &entry0, &entry1 };

    const response = limine.MemmapResponse{
        .revision = 0,
        .entry_count = 2,
        .entries = @ptrCast(&entries),
    };

    memory_map.loadMap(&response);

    try std.testing.expectEqual(@as(usize, 2), memory_map.regionCount());
    const regions = memory_map.regionsSlice();
    try std.testing.expect(regions[0].kind == .conventional);
    try std.testing.expect(regions[0].allocatable);
    try std.testing.expect(regions[1].kind == .mmio);
    try std.testing.expect(!regions[1].allocatable);
}

test "classify Limine memory map types" {
    try std.testing.expectEqual(
        memory_map.RegionKind.conventional,
        memory_map.classifyType(@intFromEnum(limine.MemmapType.usable)),
    );
    try std.testing.expectEqual(
        memory_map.RegionKind.reserved,
        memory_map.classifyType(@intFromEnum(limine.MemmapType.reserved_mapped)),
    );
    try std.testing.expectEqual(
        memory_map.RegionKind.mmio,
        memory_map.classifyType(@intFromEnum(limine.MemmapType.framebuffer)),
    );
}

test "executable_and_modules regions are non-allocatable" {
    var entry = limine.MemmapEntry{
        .base = 0x100000,
        .length = 0x200000,
        .type = @intFromEnum(limine.MemmapType.executable_and_modules),
    };
    var entries: [1]?*limine.MemmapEntry = .{&entry};

    const response = limine.MemmapResponse{
        .revision = 0,
        .entry_count = 1,
        .entries = @ptrCast(&entries),
    };

    memory_map.loadMap(&response);

    const regions = memory_map.regionsSlice();
    try std.testing.expect(regions[0].boot_reserved);
    try std.testing.expect(!regions[0].allocatable);
    try std.testing.expectEqualStrings("kernel image", regions[0].reservation.?);
}
