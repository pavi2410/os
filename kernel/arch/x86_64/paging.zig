const address = @import("../../mm/address.zig");

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

    pub const kernel_data: u64 = present | writable;
    pub const kernel_code: u64 = present;
    pub const kernel_rw: u64 = present | writable;
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

const pool_size = 32;
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

fn tablePhys(table: *PageTable) u64 {
    return address.virtToPhys(@intFromPtr(table));
}

fn getOrCreateTable(parent: *PageTable, index: u9, flags: u64) MapError!*PageTable {
    const entry = &parent[index];
    if (isPresent(entry.*)) {
        if (isHuge(entry.*)) return MapError.HugePageConflict;
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
    if (virt & (page_size - 1) != 0) return false;

    const idx = virtIndices(virt);
    const pml4 = tableFromPhys(readCr3());

    const pdpt_entry = pml4[idx.pml4];
    if (!isPresent(pdpt_entry) or isHuge(pdpt_entry)) return false;
    const pdpt = tableFromPhys(physAddr(pdpt_entry));

    const pd_entry = pdpt[idx.pdpt];
    if (!isPresent(pd_entry) or isHuge(pd_entry)) return false;
    const pd = tableFromPhys(physAddr(pd_entry));

    const pt_entry = pd[idx.pd];
    if (!isPresent(pt_entry) or isHuge(pt_entry)) return false;
    const pt = tableFromPhys(physAddr(pt_entry));

    return isPresent(pt[idx.pt]);
}
