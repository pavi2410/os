const address = @import("../../mm/address.zig");
const physical = @import("../../mm/physical.zig");

pub const page_size: u64 = 4096;
pub const page_shift: u6 = 12;
pub const entries_per_table = 512;

pub const PageTable = [entries_per_table]u64;

pub const Flags = struct {
    pub const present: u64 = 1 << 0;
    pub const writable: u64 = 1 << 1;
    pub const user: u64 = 1 << 2;
    pub const write_through: u64 = 1 << 3;
    pub const cache_disable: u64 = 1 << 4;
    pub const accessed: u64 = 1 << 5;
    pub const dirty: u64 = 1 << 6;
    pub const huge: u64 = 1 << 7;
    pub const global: u64 = 1 << 8;
    pub const no_exec: u64 = 1 << 63;

    pub const kernel_data: u64 = present | writable | no_exec;
    pub const kernel_code: u64 = present;
    pub const kernel_rw: u64 = present | writable;
    pub const mmio: u64 = present | writable | cache_disable | no_exec;
};

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

pub inline fn isPresent(entry: u64) bool {
    return entry & Flags.present != 0;
}

pub inline fn isHuge(entry: u64) bool {
    return entry & Flags.huge != 0;
}

pub inline fn physAddr(entry: u64) u64 {
    return entry & 0x000ffffffffff000;
}

pub inline fn makeEntry(phys: u64, flags: u64) u64 {
    return (phys & 0x000ffffffffff000) | flags;
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
    @memset(table, 0);
    return table;
}

fn tablePhysFrom(table: *PageTable) u64 {
    return address.virtToPhys(@intFromPtr(table));
}

fn getOrCreateTablePhys(parent: *PageTable, index: u9, flags: u64) MapError!*PageTable {
    const entry = &parent[index];
    if (isPresent(entry.*)) {
        if (isHuge(entry.*)) return MapError.HugePageConflict;
        if (flags & Flags.user != 0) entry.* |= Flags.user;
        return tableFromPhys(physAddr(entry.*));
    }

    const table = try allocTablePhys();
    entry.* = makeEntry(tablePhysFrom(table), flags | Flags.present | Flags.writable);
    return table;
}

fn tablePhys(table: *PageTable) u64 {
    return address.virtToPhys(@intFromPtr(table));
}

fn getOrCreateTable(parent: *PageTable, index: u9, flags: u64) MapError!*PageTable {
    const entry = &parent[index];
    if (isPresent(entry.*)) {
        if (isHuge(entry.*)) return MapError.HugePageConflict;
        if (flags & Flags.user != 0) entry.* |= Flags.user;
        return tableFromPhys(physAddr(entry.*));
    }

    const table = try allocTable();
    entry.* = makeEntry(tablePhys(table), flags | Flags.present | Flags.writable);
    return table;
}

pub fn mapPage(virt: u64, phys: u64, flags: u64) MapError!void {
    if (virt & (page_size - 1) != 0 or phys & (page_size - 1) != 0) {
        return MapError.UnalignedAddress;
    }

    const idx = virtIndices(virt);
    const pml4 = tableFromPhys(readCr3());

    const pdpt = try getOrCreateTable(pml4, idx.pml4, Flags.writable);
    const pd = try getOrCreateTable(pdpt, idx.pdpt, Flags.writable);
    const pt = try getOrCreateTable(pd, idx.pd, Flags.writable);

    const leaf = &pt[idx.pt];
    if (isPresent(leaf.*)) return MapError.AlreadyMapped;

    leaf.* = makeEntry(phys, flags | Flags.present);
    invlpg(virt);
}

/// Map a page for ring-3 access; sets the user flag on intermediate tables too.
pub fn mapUserPage(virt: u64, phys: u64, flags: u64) MapError!void {
    if (virt & (page_size - 1) != 0 or phys & (page_size - 1) != 0) {
        return MapError.UnalignedAddress;
    }

    const table_flags = Flags.writable | Flags.user;
    const idx = virtIndices(virt);
    const pml4 = tableFromPhys(readCr3());

    if (pml4[idx.pml4] & Flags.present != 0) pml4[idx.pml4] |= Flags.user;
    const pdpt = try getOrCreateTable(pml4, idx.pml4, table_flags);
    const pd = try getOrCreateTable(pdpt, idx.pdpt, table_flags);
    const pt = try getOrCreateTable(pd, idx.pd, table_flags);

    const leaf = &pt[idx.pt];
    if (isPresent(leaf.*)) return MapError.AlreadyMapped;

    leaf.* = makeEntry(phys, flags | Flags.present | Flags.user);
    invlpg(virt);
}

pub fn setPageFlags(virt: u64, flags: u64) MapError!void {
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

    const phys = physAddr(leaf.*);
    leaf.* = makeEntry(phys, flags | Flags.present);
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

    leaf.* = 0;
    invlpg(virt);
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

/// Allocate a fresh PML4 with the kernel higher-half entries shared from the boot tables.
pub fn createUserAddressSpace() MapError!u64 {
    const pml4 = try allocTablePhys();
    const kernel_pml4 = tableFromPhys(readCr3());

    var i: usize = kernel_pml4_start;
    while (i < entries_per_table) : (i += 1) {
        pml4[i] = kernel_pml4[i];
    }

    return tablePhysFrom(pml4);
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
            physical.freePage(physAddr(entry)) catch {};
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
pub fn mapUserPageIn(cr3_phys: u64, virt: u64, phys: u64, flags: u64) MapError!void {
    if (virt & (page_size - 1) != 0 or phys & (page_size - 1) != 0) {
        return MapError.UnalignedAddress;
    }

    const table_flags = Flags.writable | Flags.user;
    const idx = virtIndices(virt);
    const pml4 = tableFromPhys(cr3_phys);

    if (pml4[idx.pml4] & Flags.present != 0) pml4[idx.pml4] |= Flags.user;
    const pdpt = try getOrCreateTablePhys(pml4, idx.pml4, table_flags);
    const pd = try getOrCreateTablePhys(pdpt, idx.pdpt, table_flags);
    const pt = try getOrCreateTablePhys(pd, idx.pd, table_flags);

    const leaf = &pt[idx.pt];
    if (isPresent(leaf.*)) return MapError.AlreadyMapped;

    leaf.* = makeEntry(phys, flags | Flags.present | Flags.user);
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

pub fn getPageFlagsIn(cr3_phys: u64, virt: u64) ?u64 {
    const leaf = getLeafEntryIn(cr3_phys, virt) orelse return null;
    return leaf & 0x8000000000000fff;
}

fn getLeafEntryIn(cr3_phys: u64, virt: u64) ?u64 {
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

pub fn setPageFlagsIn(cr3_phys: u64, virt: u64, flags: u64) MapError!void {
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

    const phys = physAddr(leaf.*);
    leaf.* = makeEntry(phys, flags | Flags.present | Flags.user);
}
