const paging = @import("../arch/x86_64/paging.zig");
const physical = @import("physical.zig");

pub const page_size = paging.page_size;

pub const VirtError = error{
    OutOfVirtualMemory,
    OutOfMemory,
    UnalignedAddress,
    NotMapped,
};

extern var _kernel_end: u8;

/// Kernel-only dynamic mapping window (above the linked image, below the page-fault probe).
pub const kernel_heap_size: u64 = 256 * 1024 * 1024;

var heap_base: u64 = 0;
var heap_limit: u64 = 0;
var next_virt: u64 = 0;
var mapped_page_count: usize = 0;

pub fn init() void {
    heap_base = (@intFromPtr(&_kernel_end) + page_size - 1) & ~(page_size - 1);
    heap_limit = heap_base + kernel_heap_size;
    next_virt = heap_base;
    mapped_page_count = 0;
}

/// Skip a virtual address range so later heap allocations do not overlap MMIO windows.
pub fn reserveAddressRange(end_exclusive: u64) void {
    if (next_virt < end_exclusive) next_virt = end_exclusive;
}

pub fn mapPages(virt: u64, phys: u64, count: usize, perm: paging.Pte) VirtError!void {
    if (virt & (page_size - 1) != 0 or phys & (page_size - 1) != 0) {
        return VirtError.UnalignedAddress;
    }

    var i: usize = 0;
    while (i < count) : (i += 1) {
        paging.mapKernelPage(virt + @as(u64, @intCast(i)) * page_size, phys + @as(u64, @intCast(i)) * page_size, perm) catch |err| switch (err) {
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
        paging.unmapKernelPage(virt + @as(u64, @intCast(i)) * page_size) catch |err| switch (err) {
            paging.MapError.NotMapped => return VirtError.NotMapped,
            paging.MapError.UnalignedAddress => return VirtError.UnalignedAddress,
            else => return VirtError.NotMapped,
        };
    }
    mapped_page_count -= count;
}

pub fn mapMmio(phys: u64) VirtError!u64 {
    return mapMmioPages(phys, 1);
}

pub fn mapMmioPages(phys: u64, count: usize) VirtError!u64 {
    const page_phys = phys & ~(page_size - 1);
    const page_off = phys & (page_size - 1);

    const virt_page = next_virt;
    const bytes = @as(u64, @intCast(count)) * page_size;
    if (virt_page + bytes > heap_limit) return VirtError.OutOfVirtualMemory;
    next_virt += bytes;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        try mapPages(
            virt_page + @as(u64, @intCast(i)) * page_size,
            page_phys + @as(u64, @intCast(i)) * page_size,
            1,
            paging.Pte.mmio,
        );
    }
    return virt_page + page_off;
}

pub fn allocPages(count: usize) VirtError!u64 {
    if (count == 0) return VirtError.UnalignedAddress;

    const virt = next_virt;
    const bytes = @as(u64, @intCast(count)) * page_size;
    if (virt + bytes > heap_limit) return VirtError.OutOfVirtualMemory;
    next_virt += bytes;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const phys = physical.allocPage() catch return VirtError.OutOfMemory;
        try mapPages(virt + @as(u64, @intCast(i)) * page_size, phys, 1, paging.Pte.kernel_data);
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
