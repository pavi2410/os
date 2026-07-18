const address = @import("address.zig");
const paging = @import("../arch/x86_64/paging.zig");
const page_ref = @import("page_ref.zig");
const physical = @import("physical.zig");
const tlb = @import("tlb.zig");

/// Copy-on-write fork: share parent's present user pages into `dst_cr3`.
///
/// Two phases so a failed share never write-protects the parent:
/// 1. Map each parent leaf into the child (R/O + COW when it was writable) and retain.
/// 2. Write-protect those same pages in the parent and invalidate the TLB.
pub fn shareForFork(src_cr3: u64, dst_cr3: u64) paging.MapError!void {
    var map_ctx = MapChildCtx{ .dst_cr3 = dst_cr3 };
    try paging.forEachUserLeaf(src_cr3, @ptrCast(&map_ctx), mapChildLeaf);

    var protect_ctx = ProtectParentCtx{ .src_cr3 = src_cr3 };
    try paging.forEachUserLeaf(src_cr3, @ptrCast(&protect_ctx), protectParentLeaf);
}

const MapChildCtx = struct {
    dst_cr3: u64,
};

fn mapChildLeaf(ctx_ptr: *anyopaque, virt: u64, leaf: paging.Pte) paging.MapError!void {
    const ctx: *MapChildCtx = @ptrCast(@alignCast(ctx_ptr));
    const phys = leaf.framePhys();

    var child_pte = leaf;
    // Writable (or already-COW) pages must fault on write in the child too.
    if (child_pte.writable != 0 or child_pte.cow != 0) {
        child_pte.markCowShared();
    }

    // Every present user leaf must own a page_ref. Repair missing parent ownership
    // before adding the child's claim — otherwise child teardown can free a frame
    // the parent still maps (use-after-free / silent corruption).
    if (page_ref.count(phys) == 0) {
        page_ref.retain(phys) catch return paging.MapError.OutOfTables;
    }

    // Retain before map so a failed map never leaves an uncounted child PTE, and a
    // failed retain never maps a frame the teardown path would incorrectly release.
    page_ref.retain(phys) catch return paging.MapError.OutOfTables;
    errdefer page_ref.release(phys) catch {};

    try paging.mapUserPageIn(ctx.dst_cr3, virt, phys, child_pte);
}

const ProtectParentCtx = struct {
    src_cr3: u64,
};

fn protectParentLeaf(ctx_ptr: *anyopaque, virt: u64, leaf: paging.Pte) paging.MapError!void {
    const ctx: *ProtectParentCtx = @ptrCast(@alignCast(ctx_ptr));
    if (leaf.writable == 0) return;

    try paging.writeUserLeafFlagsIn(ctx.src_cr3, virt, false, true);
    tlb.invalidatePage(ctx.src_cr3, virt);
}

/// Break COW for `virt` in `cr3`. Install the new mapping before releasing the old frame.
pub fn promoteOnWrite(cr3: u64, fault_addr: u64) bool {
    const virt = fault_addr & ~(paging.page_size - 1);

    var pte = paging.getLeafEntryIn(cr3, virt) orelse return false;
    if (pte.writable != 0) return true;
    if (pte.cow == 0) return false;

    const old_phys = pte.framePhys();
    pte.writable = 1;
    pte.clearCow();

    if (page_ref.count(old_phys) <= 1) {
        paging.remapUserPageIn(cr3, virt, old_phys, pte) catch return false;
        tlb.invalidatePage(cr3, virt);
        return true;
    }

    const new_phys = physical.allocPage() catch return false;
    const src = @as([*]const u8, @ptrFromInt(address.physToVirt(old_phys)));
    const dst = @as([*]u8, @ptrFromInt(address.physToVirt(new_phys)));
    @memcpy(dst[0..paging.page_size], src[0..paging.page_size]);

    page_ref.retain(new_phys) catch {
        physical.freePage(new_phys) catch {};
        return false;
    };

    paging.remapUserPageIn(cr3, virt, new_phys, pte) catch {
        page_ref.release(new_phys) catch {};
        return false;
    };

    // Mapping now owns `new_phys`; drop this address space's claim on the shared frame.
    page_ref.release(old_phys) catch {};

    tlb.invalidatePage(cr3, virt);
    return true;
}
