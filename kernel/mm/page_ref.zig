const heap = @import("heap.zig");
const physical = @import("physical.zig");
const page_ref_table = @import("page_ref_table.zig");

pub const page_size = physical.page_size;
pub const PageRefTable = page_ref_table.PageRefTable;
pub const pfnOf = page_ref_table.pfnOf;

pub const RefError = error{
    OutOfMemory,
} || page_ref_table.RefError;

var table: PageRefTable = undefined;

pub fn init(max_pfn: usize) RefError!void {
    const bytes = (max_pfn + 1) * @sizeOf(u32);
    const mem = heap.kmalloc(bytes) catch return RefError.OutOfMemory;
    const counts = @as([*]u32, @ptrCast(@alignCast(mem)))[0 .. max_pfn + 1];
    table = PageRefTable.initFromMaxPfn(counts, max_pfn);
}

pub fn retain(phys: u64) RefError!void {
    return table.retain(phys);
}

pub fn release(phys: u64) RefError!void {
    if (try table.release(phys)) {
        physical.freePage(phys) catch {};
    }
}

pub fn count(phys: u64) u32 {
    return table.count(phys);
}
