const std = @import("std");
const uefi = std.os.uefi;
const fmt = std.fmt;

const W = std.unicode.utf8ToUtf16LeStringLiteral;

pub fn main() void {
    const con_out = uefi.system_table.con_out.?;
    _ = con_out.clearScreen();

    printf("Hello\r\nyeah\r\n", .{});

    displayMemoryMap();

    while (true) {}
}

pub fn printf(comptime format: [:0]const u8, args: anytype) void {
    const con_out = uefi.system_table.con_out.?;

    var buf8: [256]u8 = undefined;
    const msg = fmt.bufPrintZ(buf8[0..], format, args) catch unreachable;

    var buf16: [256]u16 = undefined;
    const idx = std.unicode.utf8ToUtf16Le(buf16[0..], msg) catch unreachable;
    buf16[idx] = 0;
    _ = con_out.outputString(@ptrCast(buf16[0..]));
}

fn displayMemoryMap() void {
    const boot_services = uefi.system_table.boot_services.?;

    const MemoryDescriptor = uefi.tables.MemoryDescriptor;
    const MemoryType = uefi.tables.MemoryType;

    var mmap_size: usize = 0;
    var map_key: usize = 0;
    var desc_size: usize = 0;
    var desc_version: u32 = 0;

    const status = boot_services.getMemoryMap(
        &mmap_size,
        null,
        &map_key,
        &desc_size,
        &desc_version,
    );

    if (status != .buffer_too_small) {
        printf("Failed to retrieve memory map. status = {}\r\n", .{
            status,
        });
        return;
    }

    mmap_size += 512;

    var mmap_ptr: [*]align(8) u8 = undefined;

    const alloc_status = boot_services.allocatePool(MemoryType.loader_data, mmap_size, @ptrCast(&mmap_ptr));
    if (alloc_status != .success) {
        printf("Failed to allocate memory for memory map. status = {}\r\n", .{alloc_status});
        return;
    }

    const status2 = boot_services.getMemoryMap(
        &mmap_size,
        @ptrCast(mmap_ptr),
        &map_key,
        &desc_size,
        &desc_version,
    );

    if (status2 != .success) {
        printf("Failed to retrieve memory map. status = {}\r\n", .{status2});
        return;
    }

    printf("Memory map retrieved successfully.\r\n", .{});

    const desc_count = mmap_size / desc_size;

    printf("Memory map size: {d} bytes, Descriptor size: {d} bytes, Descriptor count: {d}\r\n", .{
        mmap_size, desc_size, desc_count,
    });

    var b: usize = 0;
    var i: usize = 0;
    while (i < desc_count) : (i += 1) {
        const desc_offset = i * desc_size;
        const desc_ptr = @as(*MemoryDescriptor, @ptrCast(@alignCast(mmap_ptr + desc_offset)));

        const typ = @tagName(desc_ptr.type);
        const addr = desc_ptr.physical_start;
        const pages = desc_ptr.number_of_pages;

        if (desc_ptr.type == MemoryType.conventional_memory) {
            b += 1;
            printf("    Type:{s} Addr:{x} Pages:{d}\r\n", .{ typ, addr, pages });
        }
    }

    printf("Conventional memory blocks: {d}\r\n", .{b});
}
