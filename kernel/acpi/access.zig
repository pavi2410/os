const address = @import("../mm/address.zig");
const bytes = @import("common_bytes");

pub fn physBytes(phys: u64) [*]const u8 {
    return @ptrFromInt(address.physToVirt(phys));
}

pub fn virtBytes(virt: u64) [*]const u8 {
    return @ptrFromInt(virt);
}

pub fn sigEq4At(table: []const u8, off: usize, expected: [4]u8) bool {
    return table[off] == expected[0] and
        table[off + 1] == expected[1] and
        table[off + 2] == expected[2] and
        table[off + 3] == expected[3];
}

pub fn sigEq8At(table: []const u8, off: usize, expected: []const u8) bool {
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        if (table[off + i] != expected[i]) return false;
    }
    return true;
}

pub const sdt_header_size = 36;

/// Resolve the XSDT (preferred) or RSDT physical address from a Limine HHDM RSDP pointer.
pub fn rootTablePhys(rsdp_virt: u64) ?u64 {
    const rsdp = virtBytes(rsdp_virt);
    const rsdp_bytes = rsdp[0..36];
    if (!sigEq8At(rsdp_bytes, 0, "RSD PTR ")) return null;

    const revision = rsdp_bytes[15];
    if (revision >= 2) {
        const xsdt = bytes.readU64Le(rsdp_bytes, 24);
        if (xsdt != 0) return xsdt;
    }

    const rsdt = bytes.readU32Le(rsdp_bytes, 16);
    if (rsdt != 0) return rsdt;
    return null;
}

pub fn findTablePhys(root_phys: u64, signature: [4]u8) ?u64 {
    if (root_phys == 0) return null;
    const root = physBytes(root_phys);
    const length = bytes.readU32Le(root[0..8], 4);
    if (length < sdt_header_size) return null;
    const root_bytes = root[0..length];

    if (sigEq4At(root_bytes, 0, .{ 'X', 'S', 'D', 'T' })) {
        const entry_bytes = length - sdt_header_size;
        const entry_count = entry_bytes / 8;
        var i: usize = 0;
        while (i < entry_count) : (i += 1) {
            const table_phys = bytes.readU64Le(root_bytes, sdt_header_size + i * 8);
            if (table_phys == 0) continue;
            const table = physBytes(table_phys);
            if (sigEq4At(table[0..8], 0, signature)) return table_phys;
        }
        return null;
    }

    if (sigEq4At(root_bytes, 0, .{ 'R', 'S', 'D', 'T' })) {
        const entry_bytes = length - sdt_header_size;
        const entry_count = entry_bytes / 4;
        var i: usize = 0;
        while (i < entry_count) : (i += 1) {
            const table_phys = @as(u64, bytes.readU32Le(root_bytes, sdt_header_size + i * 4));
            if (table_phys == 0) continue;
            const table = physBytes(table_phys);
            if (sigEq4At(table[0..8], 0, signature)) return table_phys;
        }
        return null;
    }

    return null;
}
