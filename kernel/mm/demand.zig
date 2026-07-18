const address = @import("address.zig");
const paging = @import("../arch/x86_64/paging.zig");
const page_ref = @import("page_ref.zig");
const physical = @import("physical.zig");
const process = @import("../proc/process.zig");
const vma = @import("vma.zig");
const file_cache = @import("../fs/file_cache.zig");
const filesystem = @import("../fs/filesystem.zig");
const fat32 = @import("../fs/fat32.zig");

const PfErr = packed struct(u64) {
    present: u1,
    write: u1,
    user: u1,
    reserved: u1,
    fetch: u1,
    _: u59 = 0,
};

pub fn pteFromProt(prot: u32) paging.Pte {
    var pte = paging.Pte{ .present = 1, .user = 1 };
    if (prot & vma.PROT_WRITE != 0) pte.writable = 1;
    if (prot & vma.PROT_EXEC == 0) pte.no_exec = 1;
    return pte;
}

/// Ensure `virt`'s page is present for read or write access (syscall copy paths).
/// Returns true if the page was already mapped or was successfully demand-filled.
pub fn ensureMapped(proc: *process.Process, virt: u64, for_write: bool) bool {
    const page = virt & ~(paging.page_size - 1);
    if (paging.getPhysIn(proc.address_space.cr3, page) != null) return true;

    const region = proc.vmas.find(page) orelse return false;
    if (for_write) {
        if (!region.isWritable()) return false;
    } else if (!region.isReadable()) {
        return false;
    }
    return populatePage(proc, region, page);
}

/// Allocate and map a zero page for a non-present fault in an anonymous/heap/stack VMA.
/// Called only after the COW path declines the fault.
pub fn tryHandleUserPageFault(fault_addr: u64, error_code: u64) bool {
    const err: PfErr = @bitCast(error_code);
    if (err.user == 0 or err.present != 0) return false;

    const proc = process.currentProcess() orelse return false;
    const region = proc.vmas.find(fault_addr) orelse return false;

    if (err.write != 0 and !region.isWritable()) return false;
    if (err.fetch != 0 and !region.isExecutable()) return false;
    if (err.write == 0 and err.fetch == 0 and !region.isReadable()) return false;

    const virt = fault_addr & ~(paging.page_size - 1);
    if (paging.getPhysIn(proc.address_space.cr3, virt) != null) return false;
    return populatePage(proc, region, virt);
}

fn populatePage(proc: *process.Process, region: vma.Vma, page: u64) bool {
    if (region.kind == .file) {
        return mapFilePage(proc, region, page);
    }

    switch (region.kind) {
        .anon, .heap, .stack => {},
        .elf, .file, .none => return false,
    }

    const phys = physical.allocPage() catch return false;
    const buf = @as([*]u8, @ptrFromInt(address.physToVirt(phys)))[0..paging.page_size];
    @memset(buf, 0);

    const perm = pteFromProt(region.prot);
    paging.mapUserPageIn(proc.address_space.cr3, page, phys, perm) catch {
        physical.freePage(phys) catch {};
        return false;
    };
    page_ref.retain(phys) catch {
        paging.unmapUserPageIn(proc.address_space.cr3, page) catch {};
        return false;
    };

    const tlb = @import("tlb.zig");
    tlb.invalidatePage(proc.address_space.cr3, page);
    return true;
}

fn openFileFromVma(region: vma.Vma) filesystem.OpenFile {
    return .{
        .id = .{ .a = region.file.file_a, .b = region.file.file_b },
        .start_cluster = region.file.start_cluster,
        .size = region.file.file_size,
        .attr = region.file.attr,
        .loc_cluster = region.file.loc_cluster,
        .loc_offset = region.file.loc_offset,
    };
}

fn mapFilePage(proc: *process.Process, region: vma.Vma, virt: u64) bool {
    const page_index = (region.file.file_offset + (virt - region.base)) / paging.page_size;
    const open = openFileFromVma(region);
    const phys = file_cache.pinPage(&fat32.ops, open, page_index) catch return false;
    page_ref.retain(phys) catch {
        file_cache.unpinPage(&fat32.ops, open, page_index);
        return false;
    };
    const perm = pteFromProt(region.prot);
    paging.mapUserPageIn(proc.address_space.cr3, virt, phys, perm) catch {
        page_ref.release(phys) catch {};
        file_cache.unpinPage(&fat32.ops, open, page_index);
        return false;
    };
    const tlb = @import("tlb.zig");
    tlb.invalidatePage(proc.address_space.cr3, virt);
    return true;
}
