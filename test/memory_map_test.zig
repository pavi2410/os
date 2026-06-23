const std = @import("std");
const memory_map = @import("memory_map");
const shared = @import("shared");

test "parse descriptor with 48-byte stride" {
    var buffer: [96]u8 align(8) = [_]u8{0} ** 96;

    const desc0 = memory_map.UefiDescriptor{
        .type = @intFromEnum(memory_map.UefiMemoryType.conventional),
        .physical_start = 0x100000,
        .virtual_start = 0x100000,
        .number_of_pages = 16,
        .attribute = 0,
    };
    const desc1 = memory_map.UefiDescriptor{
        .type = @intFromEnum(memory_map.UefiMemoryType.mmio),
        .physical_start = 0xFED00000,
        .virtual_start = 0xFED00000,
        .number_of_pages = 1,
        .attribute = 0,
    };

    @memcpy(buffer[0..@sizeOf(memory_map.UefiDescriptor)], std.mem.asBytes(&desc0));
    @memcpy(buffer[48..][0..@sizeOf(memory_map.UefiDescriptor)], std.mem.asBytes(&desc1));

    const map = shared.MemoryMap{
        .entries = @as([*]align(8) u8, @ptrCast(&buffer)),
        .size = 96,
        .descriptor_size = 48,
        .descriptor_version = 1,
        .count = 2,
    };

    memory_map.loadMap(&map);

    try std.testing.expectEqual(@as(usize, 2), memory_map.regionCount());
    const regions = memory_map.regionsSlice();
    try std.testing.expect(regions[0].kind == .conventional);
    try std.testing.expect(regions[0].allocatable);
    try std.testing.expect(regions[1].kind == .mmio);
    try std.testing.expect(!regions[1].allocatable);
}

test "classify UEFI memory types" {
    try std.testing.expectEqual(memory_map.RegionKind.conventional, memory_map.classifyType(@intFromEnum(memory_map.UefiMemoryType.conventional)));
    try std.testing.expectEqual(memory_map.RegionKind.runtime, memory_map.classifyType(@intFromEnum(memory_map.UefiMemoryType.runtime_services_data)));
    try std.testing.expectEqual(memory_map.RegionKind.mmio, memory_map.classifyType(@intFromEnum(memory_map.UefiMemoryType.mmio)));
}

test "boot-owned regions become non-allocatable" {
    var buffer: [48]u8 align(8) = [_]u8{0} ** 48;
    const desc = memory_map.UefiDescriptor{
        .type = @intFromEnum(memory_map.UefiMemoryType.conventional),
        .physical_start = 0x100000,
        .virtual_start = 0x100000,
        .number_of_pages = 512,
        .attribute = 0,
    };
    @memcpy(buffer[0..@sizeOf(memory_map.UefiDescriptor)], std.mem.asBytes(&desc));

    const map = shared.MemoryMap{
        .entries = @as([*]align(8) u8, @ptrCast(&buffer)),
        .size = 48,
        .descriptor_size = 48,
        .descriptor_version = 1,
        .count = 1,
    };

    memory_map.loadMap(&map);
    memory_map.markReserved(0x100000, 0x110000, "kernel image");

    const regions = memory_map.regionsSlice();
    try std.testing.expect(regions[0].boot_reserved);
    try std.testing.expect(!regions[0].allocatable);
    try std.testing.expectEqualStrings("kernel image", regions[0].reservation.?);
}
