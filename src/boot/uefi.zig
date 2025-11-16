const std = @import("std");
const uefi = std.os.uefi;
const fmt = std.fmt;
const MemoryDescriptor = uefi.tables.MemoryDescriptor;
const MemoryType = uefi.tables.MemoryType;
const W = std.unicode.utf8ToUtf16LeStringLiteral;

pub fn clearScreen() void {
    const con_out = std.os.uefi.system_table.con_out.?;
    _ = con_out.clearScreen() catch {};
}

pub fn printf(comptime format: [:0]const u8, args: anytype) void {
    const con_out = uefi.system_table.con_out.?;

    var buf8: [256]u8 = undefined;
    const msg = fmt.bufPrintZ(buf8[0..], format, args) catch unreachable;

    var buf16: [256]u16 = undefined;
    const idx = std.unicode.utf8ToUtf16Le(buf16[0..], msg) catch unreachable;
    buf16[idx] = 0;

    _ = con_out.outputString(@ptrCast(buf16[0..])) catch {};
}

pub fn printMultine(msg: [:0]const u8) void {
    var splits = std.mem.splitScalar(u8, msg, '\n');
    while (splits.next()) |chunk| {
        printf("{s}\r\n", .{chunk});
    }
}

pub const MemoryMapInfo = struct {
    mmap_ptr: [*]align(8) u8,
    mmap_size: usize,
    desc_size: usize,
    desc_version: u32,
    desc_count: usize,
    map_key: uefi.tables.MemoryMapKey,
};

pub fn getMemoryMap() ?MemoryMapInfo {
    const boot_services = uefi.system_table.boot_services.?;

    // First, get the required size for the memory map
    const info = boot_services.getMemoryMapInfo() catch {
        printf("UEFI getMemoryMapInfo failed\r\n", .{});
        return null;
    };

    // Allocate buffer with extra space for potential changes
    // info.len is the number of descriptors, multiply by descriptor_size to get bytes
    const mmap_size = (info.len + 2) * info.descriptor_size;

    const buffer = boot_services.allocatePool(MemoryType.loader_data, mmap_size) catch {
        printf("UEFI AllocatePool failed\r\n", .{});
        return null;
    };

    // Create a properly aligned slice for getMemoryMap
    const aligned_buffer = @as([*]align(@alignOf(MemoryDescriptor)) u8, @alignCast(buffer.ptr))[0..buffer.len];

    // Get the actual memory map
    const mmap_slice = boot_services.getMemoryMap(aligned_buffer) catch {
        printf("UEFI getMemoryMap failed\r\n", .{});
        return null;
    };

    return .{
        .mmap_ptr = buffer.ptr,
        .mmap_size = mmap_slice.info.len * mmap_slice.info.descriptor_size,
        .map_key = mmap_slice.info.key,
        .desc_size = mmap_slice.info.descriptor_size,
        .desc_count = mmap_slice.info.len,
        .desc_version = mmap_slice.info.descriptor_version,
    };
}

pub fn printMemoryMap(mmap_info: MemoryMapInfo) void {
    printf("Memory map size: {d} bytes, Descriptor size: {d} bytes, Descriptor count: {d}\r\n", .{
        mmap_info.mmap_size, mmap_info.desc_size, mmap_info.desc_count,
    });

    printf("MemoryDescriptor size: {d} bytes\r\n", .{@sizeOf(MemoryDescriptor)});

    var b: usize = 0;
    var i: usize = 0;
    while (i < mmap_info.desc_count) : (i += 1) {
        const desc_offset = i * mmap_info.desc_size;
        const desc_ptr = @as(*MemoryDescriptor, @ptrCast(@alignCast(mmap_info.mmap_ptr + desc_offset)));

        const typ = @tagName(desc_ptr.type);
        const start = desc_ptr.physical_start;
        const pages = desc_ptr.number_of_pages;

        const end = start + pages * 4096;

        if (desc_ptr.type == MemoryType.conventional_memory) {
            b += 1;
            printf("  Type:{s} - {x} => {x} Pages:{d}\r\n", .{ typ, start, end, pages });
        }
    }

    printf("Conventional memory blocks: {d}\r\n", .{b});
}

pub fn exitBootServices() ?MemoryMapInfo {
    const boot_services = uefi.system_table.boot_services.?;

    // Get a fresh memory map right before exiting boot services
    const mem_map = getMemoryMap() orelse {
        printf("Failed to get memory map for exitBootServices\r\n", .{});
        return null;
    };

    // Try to exit boot services with the fresh map key
    boot_services.exitBootServices(uefi.handle, mem_map.map_key) catch {
        printf("ExitBootServices failed\r\n", .{});
        return null;
    };

    // Return the memory map for the kernel to use
    return mem_map;
}
