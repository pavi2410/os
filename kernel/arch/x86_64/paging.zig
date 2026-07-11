const address = @import("../../mm/address.zig");
const page_ref = @import("../../mm/page_ref.zig");
const physical = @import("../../mm/physical.zig");

pub const page_size: u64 = 4096;
pub const page_shift: u6 = 12;
pub const entries_per_table = 512;

/// x86-64 4-KiB page table entry (IA-32e PTE).
/// Bits 12-51 are the physical frame; only bits 9-11 and 52-62 are OS-reserved.
pub const Pte = packed struct(u64) {
    present: u1 = 0,
    writable: u1 = 0,
    user: u1 = 0,
    write_through: u1 = 0,
    cache_disable: u1 = 0,
    accessed: u1 = 0,
    dirty: u1 = 0,
    huge: u1 = 0,
    global: u1 = 0,
    avail: u3 = 0,
    phys: u40 = 0,
    cow: u1 = 0,
    avail_53: u1 = 0,
    avail_54: u1 = 0,
    avail_55: u1 = 0,
    avail_56: u1 = 0,
    avail_57: u1 = 0,
    avail_58: u1 = 0,
    avail_59_62: u4 = 0,
    no_exec: u1 = 0,

    pub inline fn encode(self: Pte) u64 {
        return @bitCast(self);
    }

    pub inline fn decode(raw: u64) Pte {
        return @bitCast(raw);
    }

    pub inline fn withPhys(self: Pte, frame_phys: u64) Pte {
        var copy = self;
        copy.phys = @truncate(frame_phys >> page_shift);
        return copy;
    }

    pub inline fn framePhys(self: Pte) u64 {
        return @as(u64, self.phys) << page_shift;
    }

    pub inline fn clearCow(self: *Pte) void {
        self.cow = 0;
    }

    pub inline fn markCowShared(self: *Pte) void {
        self.writable = 0;
        self.cow = 1;
    }

    /// Permission bits only (phys and software avail cleared).
    pub inline fn permissionsOnly(entry: Pte) Pte {
        var pte = entry;
        pte.phys = 0;
        pte.avail = 0;
        pte.cow = 0;
        pte.avail_53 = 0;
        pte.avail_54 = 0;
        pte.avail_55 = 0;
        pte.avail_56 = 0;
        pte.avail_57 = 0;
        pte.avail_58 = 0;
        pte.avail_59_62 = 0;
        return pte;
    }

    pub inline fn mergePermissions(existing: Pte, incoming: Pte) Pte {
        return .{
            .present = 1,
            .user = 1,
            .writable = existing.writable | incoming.writable,
            .write_through = existing.write_through | incoming.write_through,
            .cache_disable = existing.cache_disable | incoming.cache_disable,
            .no_exec = existing.no_exec & incoming.no_exec,
            .cow = existing.cow | incoming.cow,
            .avail = existing.avail | incoming.avail,
            .avail_53 = existing.avail_53 | incoming.avail_53,
            .avail_54 = existing.avail_54 | incoming.avail_54,
            .avail_55 = existing.avail_55 | incoming.avail_55,
            .avail_56 = existing.avail_56 | incoming.avail_56,
            .avail_57 = existing.avail_57 | incoming.avail_57,
            .avail_58 = existing.avail_58 | incoming.avail_58,
            .avail_59_62 = existing.avail_59_62 | incoming.avail_59_62,
        };
    }

    pub const kernel_data: Pte = .{ .present = 1, .writable = 1, .no_exec = 1 };
    pub const kernel_code: Pte = .{ .present = 1 };
    pub const kernel_rw: Pte = .{ .present = 1, .writable = 1 };
    pub const mmio: Pte = .{ .present = 1, .writable = 1, .cache_disable = 1, .no_exec = 1 };
    pub const user_heap: Pte = .{ .present = 1, .writable = 1, .user = 1, .no_exec = 1 };
    /// Intermediate page-table entries for user address spaces.
    pub const table_walk: Pte = .{ .present = 1, .writable = 1, .user = 1 };
};

pub const PageTable = [entries_per_table]Pte;

comptime {
    if (@bitSizeOf(Pte) != 64) @compileError("Pte must be 64 bits");
    if (@sizeOf(PageTable) != page_size) @compileError("PageTable must be one page");
    if (Pte.decode(1 << 63).no_exec != 1) @compileError("Pte.no_exec must be bit 63");
    if (Pte.decode(1 << 52).cow != 1) @compileError("Pte.cow must be bit 52, not bit 51");
}

pub const MapError = error{
    OutOfTables,
    AlreadyMapped,
    NotMapped,
    HugePageConflict,
    UnalignedAddress,
};

const VirtIndices = struct {
    pml4: u9,
    pdpt: u9,
    pd: u9,
    pt: u9,
};

const pool_size = 128;
var table_pool: [pool_size][page_size]u8 align(page_size) = undefined;
var table_pool_used: usize = 0;

/// All process page tables share the kernel half. Keep this small registry so
/// mappings added after process creation (kernel heaps, stacks and MMIO) are
/// propagated when they introduce a previously absent top-level entry.
const max_user_address_spaces = 16;
var kernel_cr3: u64 = 0;
var user_address_spaces: [max_user_address_spaces]?u64 = .{null} ** max_user_address_spaces;

pub inline fn isPresent(entry: Pte) bool {
    return entry.present != 0;
}

pub inline fn isHuge(entry: Pte) bool {
    return entry.huge != 0;
}

pub inline fn physAddr(entry: Pte) u64 {
    return entry.framePhys();
}

pub inline fn makeEntry(phys: u64, perm: Pte) Pte {
    var pte = perm;
    pte.present = 1;
    return pte.withPhys(phys);
}

pub inline fn readCr3() u64 {
    return asm volatile ("mov %%cr3, %[result]"
        : [result] "=r" (-> u64),
    );
}

pub inline fn writeCr3(cr3: u64) void {
    asm volatile ("mov %[cr3], %%cr3"
        :
        : [cr3] "r" (cr3),
    );
}

pub inline fn invlpg(virt: u64) void {
    asm volatile ("invlpg (%[virt])"
        :
        : [virt] "r" (virt),
    );
}

pub fn initKernelAddressSpace(cr3: u64) void {
    kernel_cr3 = cr3;
}

fn registerUserAddressSpace(cr3: u64) MapError!void {
    for (&user_address_spaces) |*slot| {
        if (slot.* == null) {
            slot.* = cr3;
            return;
        }
    }
    return MapError.OutOfTables;
}

fn unregisterUserAddressSpace(cr3: u64) void {
    for (&user_address_spaces) |*slot| {
        if (slot.* == cr3) {
            slot.* = null;
            return;
        }
    }
}

fn virtIndices(virt: u64) VirtIndices {
    return .{
        .pml4 = @truncate(virt >> 39),
        .pdpt = @truncate((virt >> 30) & 0x1FF),
        .pd = @truncate((virt >> 21) & 0x1FF),
        .pt = @truncate((virt >> 12) & 0x1FF),
    };
}

fn tableFromPhys(phys: u64) *PageTable {
    const virt = address.physToVirt(phys);
    return @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(virt))));
}

fn allocTable() MapError!*PageTable {
    if (table_pool_used >= pool_size) return MapError.OutOfTables;
    const page = &table_pool[table_pool_used];
    table_pool_used += 1;
    @memset(page, 0);
    return @ptrCast(@alignCast(page));
}

fn allocTablePhys() MapError!*PageTable {
    const phys = physical.allocPage() catch return MapError.OutOfTables;
    const table = tableFromPhys(phys);
    table.* = @splat(.{});
    return table;
}

fn tablePhysFrom(table: *PageTable) u64 {
    return address.virtToPhys(@intFromPtr(table));
}

fn getOrCreateTablePhys(parent: *PageTable, index: u9, walk: Pte) MapError!*PageTable {
    const entry = &parent[index];
    if (isPresent(entry.*)) {
        if (isHuge(entry.*)) return MapError.HugePageConflict;
        if (walk.user != 0) entry.user = 1;
        return tableFromPhys(physAddr(entry.*));
    }

    const table = try allocTablePhys();
    entry.* = makeEntry(tablePhysFrom(table), Pte.mergePermissions(walk, .{ .writable = 1 }));
    return table;
}

fn tablePhys(table: *PageTable) u64 {
    return address.virtToPhys(@intFromPtr(table));
}

fn getOrCreateTable(parent: *PageTable, index: u9, walk: Pte) MapError!*PageTable {
    const entry = &parent[index];
    if (isPresent(entry.*)) {
        if (isHuge(entry.*)) return MapError.HugePageConflict;
        if (walk.user != 0) entry.user = 1;
        return tableFromPhys(physAddr(entry.*));
    }

    const table = try allocTable();
    entry.* = makeEntry(tablePhys(table), Pte.mergePermissions(walk, .{ .writable = 1 }));
    return table;
}

pub fn mapPage(virt: u64, phys: u64, perm: Pte) MapError!void {
    if (virt & (page_size - 1) != 0 or phys & (page_size - 1) != 0) {
        return MapError.UnalignedAddress;
    }

    const idx = virtIndices(virt);
    const pml4 = tableFromPhys(readCr3());

    const pdpt = try getOrCreateTable(pml4, idx.pml4, .{ .writable = 1 });
    const pd = try getOrCreateTable(pdpt, idx.pdpt, .{ .writable = 1 });
    const pt = try getOrCreateTable(pd, idx.pd, .{ .writable = 1 });

    const leaf = &pt[idx.pt];
    if (isPresent(leaf.*)) return MapError.AlreadyMapped;

    leaf.* = makeEntry(phys, perm);
    invlpg(virt);
}

fn syncKernelTopLevelMappings() void {
    const kernel_pml4 = tableFromPhys(kernel_cr3);
    for (user_address_spaces) |maybe_cr3| {
        const cr3 = maybe_cr3 orelse continue;
        const pml4 = tableFromPhys(cr3);
        var i: usize = kernel_pml4_start;
        while (i < entries_per_table) : (i += 1) {
            pml4[i] = kernel_pml4[i];
        }
    }
}

/// Add a kernel-only mapping to the shared kernel page tables. User address
/// spaces use their own PML4, so refresh their kernel-half roots afterwards.
pub fn mapKernelPage(virt: u64, phys: u64, perm: Pte) MapError!void {
    if (kernel_cr3 == 0) return MapError.OutOfTables;
    const active_cr3 = readCr3();
    writeCr3(kernel_cr3);
    defer writeCr3(active_cr3);
    try mapPage(virt, phys, perm);
    syncKernelTopLevelMappings();
}

/// Map a page for ring-3 access; sets the user flag on intermediate tables too.
pub fn mapUserPage(virt: u64, phys: u64, perm: Pte) MapError!void {
    if (virt & (page_size - 1) != 0 or phys & (page_size - 1) != 0) {
        return MapError.UnalignedAddress;
    }

    const idx = virtIndices(virt);
    const pml4 = tableFromPhys(readCr3());

    if (isPresent(pml4[idx.pml4])) pml4[idx.pml4].user = 1;
    const pdpt = try getOrCreateTable(pml4, idx.pml4, Pte.table_walk);
    const pd = try getOrCreateTable(pdpt, idx.pdpt, Pte.table_walk);
    const pt = try getOrCreateTable(pd, idx.pd, Pte.table_walk);

    const leaf = &pt[idx.pt];
    if (isPresent(leaf.*)) return MapError.AlreadyMapped;

    leaf.* = makeEntry(phys, Pte.mergePermissions(perm, .{ .user = 1 }));
    invlpg(virt);
}

pub fn setPageFlags(virt: u64, perm: Pte) MapError!void {
    if (virt & (page_size - 1) != 0) return MapError.UnalignedAddress;

    const idx = virtIndices(virt);
    const pml4 = tableFromPhys(readCr3());

    const pdpt_entry = pml4[idx.pml4];
    if (!isPresent(pdpt_entry) or isHuge(pdpt_entry)) return MapError.NotMapped;
    const pdpt = tableFromPhys(physAddr(pdpt_entry));

    const pd_entry = pdpt[idx.pdpt];
    if (!isPresent(pd_entry) or isHuge(pd_entry)) return MapError.NotMapped;
    const pd = tableFromPhys(physAddr(pd_entry));

    const pt_entry = pd[idx.pd];
    if (!isPresent(pt_entry) or isHuge(pt_entry)) return MapError.NotMapped;
    const pt = tableFromPhys(physAddr(pt_entry));

    const leaf = &pt[idx.pt];
    if (!isPresent(leaf.*)) return MapError.NotMapped;

    leaf.* = makeEntry(leaf.framePhys(), perm);
    invlpg(virt);
}

pub fn unmapPage(virt: u64) MapError!void {
    if (virt & (page_size - 1) != 0) return MapError.NotMapped;

    const idx = virtIndices(virt);
    const pml4 = tableFromPhys(readCr3());

    const pdpt_entry = pml4[idx.pml4];
    if (!isPresent(pdpt_entry)) return MapError.NotMapped;
    if (isHuge(pdpt_entry)) return MapError.HugePageConflict;
    const pdpt = tableFromPhys(physAddr(pdpt_entry));

    const pd_entry = pdpt[idx.pdpt];
    if (!isPresent(pd_entry)) return MapError.NotMapped;
    if (isHuge(pd_entry)) return MapError.HugePageConflict;
    const pd = tableFromPhys(physAddr(pd_entry));

    const pt_entry = pd[idx.pd];
    if (!isPresent(pt_entry)) return MapError.NotMapped;
    if (isHuge(pt_entry)) return MapError.HugePageConflict;
    const pt = tableFromPhys(physAddr(pt_entry));

    const leaf = &pt[idx.pt];
    if (!isPresent(leaf.*)) return MapError.NotMapped;

    leaf.* = .{};
    invlpg(virt);
}

pub fn unmapKernelPage(virt: u64) MapError!void {
    if (kernel_cr3 == 0) return MapError.NotMapped;
    const active_cr3 = readCr3();
    writeCr3(kernel_cr3);
    defer writeCr3(active_cr3);
    try unmapPage(virt);
    syncKernelTopLevelMappings();
}

pub fn isMapped(virt: u64) bool {
    return getPhys(virt) != null;
}

pub fn getPhys(virt: u64) ?u64 {
    if (virt & (page_size - 1) != 0) return null;

    const idx = virtIndices(virt);
    const pml4 = tableFromPhys(readCr3());

    const pdpt_entry = pml4[idx.pml4];
    if (!isPresent(pdpt_entry) or isHuge(pdpt_entry)) return null;
    const pdpt = tableFromPhys(physAddr(pdpt_entry));

    const pd_entry = pdpt[idx.pdpt];
    if (!isPresent(pd_entry) or isHuge(pd_entry)) return null;
    const pd = tableFromPhys(physAddr(pd_entry));

    const pt_entry = pd[idx.pd];
    if (!isPresent(pt_entry) or isHuge(pt_entry)) return null;
    const pt = tableFromPhys(physAddr(pt_entry));

    const leaf = pt[idx.pt];
    if (!isPresent(leaf)) return null;
    return physAddr(leaf);
}

/// First PML4 index that maps the kernel higher half.
const kernel_pml4_start: usize = 256;

fn virtFromIndices(pml4_idx: usize, pdpt_idx: usize, pd_idx: usize, pt_idx: usize) u64 {
    return (@as(u64, pml4_idx) << 39) |
        (@as(u64, pdpt_idx) << 30) |
        (@as(u64, pd_idx) << 21) |
        (@as(u64, pt_idx) << 12);
}

/// Share mapped user pages from `src_cr3` into `dst_cr3` (copy-on-write).
pub fn shareUserAddressSpace(src_cr3: u64, dst_cr3: u64) MapError!void {
    const src_pml4 = tableFromPhys(src_cr3);

    var pml4_idx: usize = 0;
    while (pml4_idx < kernel_pml4_start) : (pml4_idx += 1) {
        const pdpt_entry = src_pml4[pml4_idx];
        if (!isPresent(pdpt_entry) or isHuge(pdpt_entry)) continue;

        const src_pdpt = tableFromPhys(physAddr(pdpt_entry));
        var pdpt_idx: usize = 0;
        while (pdpt_idx < entries_per_table) : (pdpt_idx += 1) {
            const pd_entry = src_pdpt[pdpt_idx];
            if (!isPresent(pd_entry) or isHuge(pd_entry)) continue;

            const src_pd = tableFromPhys(physAddr(pd_entry));
            var pd_idx: usize = 0;
            while (pd_idx < entries_per_table) : (pd_idx += 1) {
                const pt_entry = src_pd[pd_idx];
                if (!isPresent(pt_entry) or isHuge(pt_entry)) continue;

                const src_pt = tableFromPhys(physAddr(pt_entry));
                var pt_idx: usize = 0;
                while (pt_idx < entries_per_table) : (pt_idx += 1) {
                    const leaf = src_pt[pt_idx];
                    if (!isPresent(leaf) or isHuge(leaf)) continue;
                    if (leaf.user == 0) continue;

                    const virt = virtFromIndices(pml4_idx, pdpt_idx, pd_idx, pt_idx);
                    const src_phys = physAddr(leaf);
                    var pte = leaf;
                    const was_writable = pte.writable != 0;
                    if (was_writable) pte.markCowShared();

                    mapUserPageIn(dst_cr3, virt, src_phys, pte) catch |err| return err;
                    page_ref.retain(src_phys) catch return MapError.OutOfTables;

                    if (was_writable) {
                        setPageFlagsIn(src_cr3, virt, pte) catch |err| return err;
                        if (src_cr3 == readCr3()) invlpg(virt);
                    }
                }
            }
        }
    }
}

/// Eagerly copy all mapped user pages from `src_cr3` into `dst_cr3` (new physical pages).
pub fn cloneUserAddressSpace(src_cr3: u64, dst_cr3: u64) MapError!void {
    const src_pml4 = tableFromPhys(src_cr3);

    var pml4_idx: usize = 0;
    while (pml4_idx < kernel_pml4_start) : (pml4_idx += 1) {
        const pdpt_entry = src_pml4[pml4_idx];
        if (!isPresent(pdpt_entry) or isHuge(pdpt_entry)) continue;

        const src_pdpt = tableFromPhys(physAddr(pdpt_entry));
        var pdpt_idx: usize = 0;
        while (pdpt_idx < entries_per_table) : (pdpt_idx += 1) {
            const pd_entry = src_pdpt[pdpt_idx];
            if (!isPresent(pd_entry) or isHuge(pd_entry)) continue;

            const src_pd = tableFromPhys(physAddr(pd_entry));
            var pd_idx: usize = 0;
            while (pd_idx < entries_per_table) : (pd_idx += 1) {
                const pt_entry = src_pd[pd_idx];
                if (!isPresent(pt_entry) or isHuge(pt_entry)) continue;

                const src_pt = tableFromPhys(physAddr(pt_entry));
                var pt_idx: usize = 0;
                while (pt_idx < entries_per_table) : (pt_idx += 1) {
                    const leaf = src_pt[pt_idx];
                    if (!isPresent(leaf) or isHuge(leaf)) continue;
                    if (leaf.user == 0) continue;

                    const virt = virtFromIndices(pml4_idx, pdpt_idx, pd_idx, pt_idx);
                    const src_phys = physAddr(leaf);
                    const perm = Pte.permissionsOnly(leaf);

                    const dst_phys = physical.allocPage() catch return MapError.OutOfTables;
                    const src_ptr = @as([*]u8, @ptrFromInt(address.physToVirt(src_phys)));
                    const dst_ptr = @as([*]u8, @ptrFromInt(address.physToVirt(dst_phys)));
                    @memcpy(dst_ptr[0..page_size], src_ptr[0..page_size]);

                    mapUserPageIn(dst_cr3, virt, dst_phys, perm) catch |err| return err;
                    page_ref.retain(dst_phys) catch return MapError.OutOfTables;
                }
            }
        }
    }
}

/// Allocate a fresh PML4 with the kernel higher-half entries shared from the boot tables.
pub fn createUserAddressSpace() MapError!u64 {
    if (kernel_cr3 == 0) return MapError.OutOfTables;
    const pml4 = try allocTablePhys();
    const kernel_pml4 = tableFromPhys(kernel_cr3);

    var i: usize = kernel_pml4_start;
    while (i < entries_per_table) : (i += 1) {
        pml4[i] = kernel_pml4[i];
    }

    const cr3 = tablePhysFrom(pml4);
    registerUserAddressSpace(cr3) catch {
        physical.freePage(cr3) catch {};
        return MapError.OutOfTables;
    };
    return cr3;
}

fn freeUserPageTableSubtree(table: *PageTable, level: usize) void {
    var i: usize = 0;
    while (i < entries_per_table) : (i += 1) {
        const entry = table[i];
        if (!isPresent(entry)) continue;
        if (isHuge(entry)) {
            physical.freePage(physAddr(entry)) catch {};
            continue;
        }

        if (level == 3) {
            page_ref.release(physAddr(entry)) catch {};
            continue;
        }

        const child = tableFromPhys(physAddr(entry));
        freeUserPageTableSubtree(child, level + 1);
        physical.freePage(physAddr(entry)) catch {};
    }
}

/// Tear down the user half of an address space and free its PML4.
pub fn destroyUserAddressSpace(cr3_phys: u64) MapError!void {
    if (cr3_phys & (page_size - 1) != 0) return MapError.UnalignedAddress;

    unregisterUserAddressSpace(cr3_phys);
    const pml4 = tableFromPhys(cr3_phys);

    var i: usize = 0;
    while (i < kernel_pml4_start) : (i += 1) {
        const entry = pml4[i];
        if (!isPresent(entry) or isHuge(entry)) continue;

        const pdpt = tableFromPhys(physAddr(entry));
        freeUserPageTableSubtree(pdpt, 1);
        physical.freePage(physAddr(entry)) catch {};
    }

    physical.freePage(cr3_phys) catch {};
}

/// Map a user-accessible page in a specific address space without switching CR3.
pub fn mapUserPageIn(cr3_phys: u64, virt: u64, phys: u64, perm: Pte) MapError!void {
    if (virt & (page_size - 1) != 0 or phys & (page_size - 1) != 0) {
        return MapError.UnalignedAddress;
    }

    const idx = virtIndices(virt);
    const pml4 = tableFromPhys(cr3_phys);

    if (isPresent(pml4[idx.pml4])) pml4[idx.pml4].user = 1;
    const pdpt = try getOrCreateTablePhys(pml4, idx.pml4, Pte.table_walk);
    const pd = try getOrCreateTablePhys(pdpt, idx.pdpt, Pte.table_walk);
    const pt = try getOrCreateTablePhys(pd, idx.pd, Pte.table_walk);

    const leaf = &pt[idx.pt];
    if (isPresent(leaf.*)) return MapError.AlreadyMapped;

    leaf.* = makeEntry(phys, Pte.mergePermissions(perm, .{ .user = 1 }));
}

pub fn getPhysIn(cr3_phys: u64, virt: u64) ?u64 {
    if (virt & (page_size - 1) != 0) return null;

    const idx = virtIndices(virt);
    const pml4 = tableFromPhys(cr3_phys);

    const pdpt_entry = pml4[idx.pml4];
    if (!isPresent(pdpt_entry) or isHuge(pdpt_entry)) return null;
    const pdpt = tableFromPhys(physAddr(pdpt_entry));

    const pd_entry = pdpt[idx.pdpt];
    if (!isPresent(pd_entry) or isHuge(pd_entry)) return null;
    const pd = tableFromPhys(physAddr(pd_entry));

    const pt_entry = pd[idx.pd];
    if (!isPresent(pt_entry) or isHuge(pt_entry)) return null;
    const pt = tableFromPhys(physAddr(pt_entry));

    const leaf = pt[idx.pt];
    if (!isPresent(leaf)) return null;
    return physAddr(leaf);
}

pub fn getPageFlagsIn(cr3_phys: u64, virt: u64) ?Pte {
    const leaf = getLeafEntryIn(cr3_phys, virt) orelse return null;
    return Pte.permissionsOnly(leaf);
}

pub fn getLeafEntryIn(cr3_phys: u64, virt: u64) ?Pte {
    if (virt & (page_size - 1) != 0) return null;

    const idx = virtIndices(virt);
    const pml4 = tableFromPhys(cr3_phys);

    const pdpt_entry = pml4[idx.pml4];
    if (!isPresent(pdpt_entry) or isHuge(pdpt_entry)) return null;
    const pdpt = tableFromPhys(physAddr(pdpt_entry));

    const pd_entry = pdpt[idx.pdpt];
    if (!isPresent(pd_entry) or isHuge(pd_entry)) return null;
    const pd = tableFromPhys(physAddr(pd_entry));

    const pt_entry = pd[idx.pd];
    if (!isPresent(pt_entry) or isHuge(pt_entry)) return null;
    const pt = tableFromPhys(physAddr(pt_entry));

    const leaf = pt[idx.pt];
    if (!isPresent(leaf)) return null;
    return leaf;
}

pub fn remapUserPageIn(cr3_phys: u64, virt: u64, phys: u64, perm: Pte) MapError!void {
    if (virt & (page_size - 1) != 0 or phys & (page_size - 1) != 0) {
        return MapError.UnalignedAddress;
    }

    const idx = virtIndices(virt);
    const pml4 = tableFromPhys(cr3_phys);

    const pdpt_entry = pml4[idx.pml4];
    if (!isPresent(pdpt_entry) or isHuge(pdpt_entry)) return MapError.NotMapped;
    const pdpt = tableFromPhys(physAddr(pdpt_entry));

    const pd_entry = pdpt[idx.pdpt];
    if (!isPresent(pd_entry) or isHuge(pd_entry)) return MapError.NotMapped;
    const pd = tableFromPhys(physAddr(pd_entry));

    const pt_entry = pd[idx.pd];
    if (!isPresent(pt_entry) or isHuge(pt_entry)) return MapError.NotMapped;
    const pt = tableFromPhys(physAddr(pt_entry));

    const leaf = &pt[idx.pt];
    if (!isPresent(leaf.*)) return MapError.NotMapped;

    leaf.* = makeEntry(phys, Pte.mergePermissions(perm, .{ .user = 1 }));
}

pub fn setPageFlagsIn(cr3_phys: u64, virt: u64, perm: Pte) MapError!void {
    if (virt & (page_size - 1) != 0) return MapError.UnalignedAddress;

    const idx = virtIndices(virt);
    const pml4 = tableFromPhys(cr3_phys);

    const pdpt_entry = pml4[idx.pml4];
    if (!isPresent(pdpt_entry) or isHuge(pdpt_entry)) return MapError.NotMapped;
    const pdpt = tableFromPhys(physAddr(pdpt_entry));

    const pd_entry = pdpt[idx.pdpt];
    if (!isPresent(pd_entry) or isHuge(pd_entry)) return MapError.NotMapped;
    const pd = tableFromPhys(physAddr(pd_entry));

    const pt_entry = pd[idx.pd];
    if (!isPresent(pt_entry) or isHuge(pt_entry)) return MapError.NotMapped;
    const pt = tableFromPhys(physAddr(pt_entry));

    const leaf = &pt[idx.pt];
    if (!isPresent(leaf.*)) return MapError.NotMapped;

    leaf.* = makeEntry(leaf.framePhys(), Pte.mergePermissions(perm, .{ .user = 1 }));
}
