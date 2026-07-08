const address = @import("address.zig");
const paging = @import("../arch/x86_64/paging.zig");
const page_ref = @import("page_ref.zig");
const physical = @import("physical.zig");
const process = @import("../proc/process.zig");

const PfErr = packed struct(u64) {
    present: u1,
    write: u1,
    user: u1,
    reserved: u1,
    fetch: u1,
    _: u59 = 0,
};

/// Handle a user write fault to a present read-only COW page. Returns true if the fault was resolved.
pub fn tryHandleUserPageFault(fault_addr: u64, error_code: u64) bool {
    const err: PfErr = @bitCast(error_code);
    if (err.fetch != 0 or err.user == 0 or err.present == 0 or err.write == 0) return false;

    const proc = process.currentProcess() orelse return false;
    const cr3 = proc.address_space.cr3;
    const virt = fault_addr & ~(paging.page_size - 1);

    var pte = paging.getLeafEntryIn(cr3, virt) orelse return false;
    if (pte.cow == 0) return false;

    const old_phys = pte.framePhys();

    const new_phys = if (page_ref.count(old_phys) <= 1) old_phys else blk: {
        const phys = physical.allocPage() catch return false;
        const src = @as([*]const u8, @ptrFromInt(address.physToVirt(old_phys)));
        const dst = @as([*]u8, @ptrFromInt(address.physToVirt(phys)));
        @memcpy(dst[0..paging.page_size], src[0..paging.page_size]);
        break :blk phys;
    };

    if (new_phys != old_phys) {
        page_ref.release(old_phys) catch return false;
    }

    pte.writable = 1;
    pte.clearCow();
    paging.remapUserPageIn(cr3, virt, new_phys, pte) catch return false;

    if (new_phys != old_phys) {
        page_ref.retain(new_phys) catch return false;
    }

    if (paging.readCr3() == cr3) paging.invlpg(virt);
    return true;
}
