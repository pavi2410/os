const std = @import("std");
const uefi = std.os.uefi;
const fmt = std.fmt;
const MemoryDescriptor = uefi.tables.MemoryDescriptor;
const MemoryType = uefi.tables.MemoryType;
const W = std.unicode.utf8ToUtf16LeStringLiteral;

pub fn clearScreen() void {
    const con_out = std.os.uefi.system_table.con_out.?;
    _ = con_out.clearScreen();
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
    map_key: usize,
};

pub fn getMemoryMap() ?MemoryMapInfo {
    const boot_services = uefi.system_table.boot_services.?;

    var mmap_size: usize = 0;
    var map_key: usize = 0;
    var desc_size: usize = 0;
    var desc_version: u32 = 0;

    var status: uefi.Status = undefined;

    status = boot_services.getMemoryMap(
        &mmap_size,
        null,
        &map_key,
        &desc_size,
        &desc_version,
    );

    if (status != .buffer_too_small) {
        printf("UEFI GetMemoryMap failed: {}\r\n", .{status});
        return null;
    }

    mmap_size += 2 * desc_size;

    var mmap_ptr: [*]align(8) u8 = undefined;

    status = boot_services.allocatePool(MemoryType.loader_data, mmap_size, @ptrCast(&mmap_ptr));

    if (status != .success) {
        printf("UEFI AllocatePool failed: {}\r\n", .{status});
        return null;
    }

    status = boot_services.getMemoryMap(
        &mmap_size,
        @ptrCast(mmap_ptr),
        &map_key,
        &desc_size,
        &desc_version,
    );

    if (status != .success) {
        printf("UEFI GetMemoryPool second attemp failed: {}\r\n", .{status});
        return null;
    }

    const desc_count = mmap_size / desc_size;

    return .{
        .mmap_ptr = mmap_ptr,
        .mmap_size = mmap_size,
        .map_key = map_key,
        .desc_size = desc_size,
        .desc_count = desc_count,
        .desc_version = desc_version,
    };
}

fn printMemoryMap(mmap_info: MemoryMapInfo) void {
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

pub fn exitBootServices(map_key: usize) bool {
    const boot_services = uefi.system_table.boot_services.?;

    const status = boot_services.exitBootServices(uefi.handle, map_key);

    if (status != .success) {
        printf("ExitBootServices failed: {}\r\n", .{status});
        return false;
    }

    return true;
}
