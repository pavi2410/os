const address = @import("address.zig");
const paging = @import("../arch/x86_64/paging.zig");
const page_ref = @import("page_ref.zig");
const physical = @import("physical.zig");
const process = @import("../proc/process.zig");
const vma = @import("vma.zig");

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

/// Allocate and map a zero page for a non-present fault in an anonymous/heap/stack VMA.
/// Called only after the COW path declines the fault.
pub fn tryHandleUserPageFault(fault_addr: u64, error_code: u64) bool {
    const err: PfErr = @bitCast(error_code);
    if (err.user == 0 or err.present != 0) return false;

    const proc = process.currentProcess() orelse return false;
    const region = proc.vmas.find(fault_addr) orelse return false;

    switch (region.kind) {
        .anon, .heap, .stack => {},
        .elf, .file, .none => return false,
    }

    if (err.write != 0 and !region.isWritable()) return false;
    if (err.fetch != 0 and !region.isExecutable()) return false;
    if (err.write == 0 and err.fetch == 0 and !region.isReadable()) return false;

    const virt = fault_addr & ~(paging.page_size - 1);
    if (paging.getPhysIn(proc.address_space.cr3, virt) != null) return false;

    const phys = physical.allocPage() catch return false;
    const buf = @as([*]u8, @ptrFromInt(address.physToVirt(phys)))[0..paging.page_size];
    @memset(buf, 0);

    const perm = pteFromProt(region.prot);
    paging.mapUserPageIn(proc.address_space.cr3, virt, phys, perm) catch {
        physical.freePage(phys) catch {};
        return false;
    };
    page_ref.retain(phys) catch {
        paging.unmapUserPageIn(proc.address_space.cr3, virt) catch {};
        return false;
    };

    if (paging.readCr3() == proc.address_space.cr3) paging.invlpg(virt);
    return true;
}
