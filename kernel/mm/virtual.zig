const paging = @import("../arch/x86_64/paging.zig");
const physical = @import("physical.zig");

pub const page_size = paging.page_size;

pub const VirtError = error{
    OutOfVirtualMemory,
    OutOfMemory,
    UnalignedAddress,
    NotMapped,
};

/// Kernel-only dynamic mapping window (above the linked image, below the page-fault probe).
pub const KERNEL_HEAP_BASE: u64 = 0xFFFFFFFF80100000;
pub const KERNEL_HEAP_LIMIT: u64 = KERNEL_HEAP_BASE + (256 * 1024 * 1024);

var next_virt: u64 = KERNEL_HEAP_BASE;
var mapped_page_count: usize = 0;

pub fn init() void {
    next_virt = KERNEL_HEAP_BASE;
    mapped_page_count = 0;
}

/// Skip a virtual address range so later heap allocations do not overlap MMIO windows.
pub fn reserveAddressRange(end_exclusive: u64) void {
    if (next_virt < end_exclusive) next_virt = end_exclusive;
}

pub fn mapPages(virt: u64, phys: u64, count: usize, flags: u64) VirtError!void {
    if (virt & (page_size - 1) != 0 or phys & (page_size - 1) != 0) {
        return VirtError.UnalignedAddress;
    }

    var i: usize = 0;
    while (i < count) : (i += 1) {
        paging.mapPage(virt + @as(u64, @intCast(i)) * page_size, phys + @as(u64, @intCast(i)) * page_size, flags) catch |err| switch (err) {
            paging.MapError.OutOfTables => return VirtError.OutOfMemory,
            paging.MapError.AlreadyMapped => return VirtError.OutOfVirtualMemory,
            paging.MapError.UnalignedAddress => return VirtError.UnalignedAddress,
            else => return VirtError.OutOfMemory,
        };
    }
    mapped_page_count += count;
}

pub fn unmapPages(virt: u64, count: usize) VirtError!void {
    if (virt & (page_size - 1) != 0) return VirtError.UnalignedAddress;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        paging.unmapPage(virt + @as(u64, @intCast(i)) * page_size) catch |err| switch (err) {
            paging.MapError.NotMapped => return VirtError.NotMapped,
            paging.MapError.UnalignedAddress => return VirtError.UnalignedAddress,
            else => return VirtError.NotMapped,
        };
    }
    mapped_page_count -= count;
}

pub fn allocPages(count: usize) VirtError!u64 {
    if (count == 0) return VirtError.UnalignedAddress;

    const virt = next_virt;
    const bytes = @as(u64, @intCast(count)) * page_size;
    if (virt + bytes > KERNEL_HEAP_LIMIT) return VirtError.OutOfVirtualMemory;
    next_virt += bytes;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const phys = physical.allocPage() catch return VirtError.OutOfMemory;
        try mapPages(virt + @as(u64, @intCast(i)) * page_size, phys, 1, paging.Flags.kernel_data);
    }

    return virt;
}

pub fn freePages(virt: u64, count: usize) VirtError!void {
    if (virt & (page_size - 1) != 0) return VirtError.UnalignedAddress;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const page_virt = virt + @as(u64, @intCast(i)) * page_size;
        const phys = paging.getPhys(page_virt) orelse return VirtError.NotMapped;
        try unmapPages(page_virt, 1);
        try physical.freePage(phys);
    }
}

pub fn mappedPages() usize {
    return mapped_page_count;
}

pub fn nextVirtualAddress() u64 {
    return next_virt;
}
