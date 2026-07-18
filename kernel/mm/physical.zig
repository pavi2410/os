const address = @import("address.zig");
const memory_map = @import("memory_map.zig");
const bitmap = @import("physical_bitmap.zig");
const std = @import("std");

pub const page_size = bitmap.page_size;
pub const page_shift: u6 = 12;
pub const Range = bitmap.Range;
pub const PageBitmap = bitmap.PageBitmap;

pub const PhysError = error{
    OutOfMemory,
    InvalidAddress,
    DoubleFree,
};

pub const PhysAddr = u64;

var allocator: PageBitmap = undefined;
var bitmap_storage: [*]u8 = undefined;
var bitmap_byte_len: usize = 0;
var max_pfn: usize = 0;

pub fn init() void {
    const regions = memory_map.regionsSlice();

    var max_addr: u64 = 0;
    for (regions) |region| {
        if (!region.allocatable) continue;
        max_addr = @max(max_addr, region.end);
    }
    if (max_addr == 0) {
        @panic("no allocatable conventional memory");
    }

    const max_pfn_val = max_addr / page_size;
    max_pfn = max_pfn_val;
    // Bits for PFNs 0..=max_pfn inclusive.
    bitmap_byte_len = (max_pfn_val / 8) + 1;
    const bitmap_page_count = (bitmap_byte_len + page_size - 1) / page_size;

    const bitmap_phys = findBitmapLocation(regions, bitmap_page_count) orelse {
        @panic("no conventional memory for physical page bitmap");
    };

    memory_map.markReserved(
        bitmap_phys,
        bitmap_phys + @as(u64, @intCast(bitmap_page_count)) * page_size,
        "physical page bitmap",
    );

    bitmap_storage = @ptrFromInt(address.physToVirt(bitmap_phys));

    var stack_ranges: [256]Range = undefined;
    var range_count: usize = 0;
    for (memory_map.regionsSlice()) |region| {
        stack_ranges[range_count] = .{
            .start = region.start,
            .end = region.end,
            .allocatable = region.allocatable,
        };
        range_count += 1;
    }

    allocator = PageBitmap.initFromRegions(bitmap_storage[0..bitmap_byte_len], stack_ranges[0..range_count]);
    allocator.markRangeUsed(bitmap_phys, bitmap_phys + @as(u64, @intCast(bitmap_page_count)) * page_size);
}

pub fn allocPage() PhysError!PhysAddr {
    return allocator.allocPage() orelse PhysError.OutOfMemory;
}

pub fn freePage(phys: PhysAddr) PhysError!void {
    allocator.freePage(phys) catch |err| switch (err) {
        error.InvalidAddress => return PhysError.InvalidAddress,
        error.DoubleFree => return PhysError.DoubleFree,
    };
}

pub fn totalPages() usize {
    return allocator.total_allocatable;
}

pub fn freePages() usize {
    return allocator.free_pages;
}

pub fn usedPages() usize {
    return allocator.usedPages();
}

pub fn maxPfn() usize {
    return max_pfn;
}

fn findBitmapLocation(regions: []const memory_map.Region, pages_needed: usize) ?PhysAddr {
    const needed_bytes = @as(u64, @intCast(pages_needed)) * page_size;

    for (regions) |region| {
        if (!region.allocatable) continue;

        var addr = std.mem.alignForward(u64, region.start, page_size);
        if (addr == 0) addr = page_size;

        if (addr + needed_bytes <= region.end) {
            return addr;
        }
    }

    return null;
}
