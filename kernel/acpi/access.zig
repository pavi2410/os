const address = @import("../mm/address.zig");

pub fn physBytes(phys: u64) [*]const u8 {
    return @ptrFromInt(address.physToVirt(phys));
}

pub fn virtBytes(virt: u64) [*]const u8 {
    return @ptrFromInt(virt);
}

pub fn readU32(bytes: [*]const u8, off: usize) u32 {
    return @as(u32, bytes[off]) |
        (@as(u32, bytes[off + 1]) << 8) |
        (@as(u32, bytes[off + 2]) << 16) |
        (@as(u32, bytes[off + 3]) << 24);
}

pub fn readU64(bytes: [*]const u8, off: usize) u64 {
    return readU32(bytes, off) | (@as(u64, readU32(bytes, off + 4)) << 32);
}

pub fn sigEq4At(bytes: [*]const u8, off: usize, expected: [4]u8) bool {
    return bytes[off] == expected[0] and
        bytes[off + 1] == expected[1] and
        bytes[off + 2] == expected[2] and
        bytes[off + 3] == expected[3];
}

pub fn sigEq8At(bytes: [*]const u8, off: usize, expected: []const u8) bool {
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        if (bytes[off + i] != expected[i]) return false;
    }
    return true;
}

pub const sdt_header_size = 36;

pub fn findTablePhys(root_phys: u64, signature: [4]u8) ?u64 {
    if (root_phys == 0) return null;
    const root = physBytes(root_phys);
    const length = readU32(root, 4);
    if (length < sdt_header_size) return null;

    if (sigEq4At(root, 0, .{ 'X', 'S', 'D', 'T' })) {
        const entry_bytes = length - sdt_header_size;
        const entry_count = entry_bytes / 8;
        var i: usize = 0;
        while (i < entry_count) : (i += 1) {
            const table_phys = readU64(root, sdt_header_size + i * 8);
            if (table_phys == 0 or table_phys >= 0x1_0000_0000) continue;
            const table = physBytes(table_phys);
            if (sigEq4At(table, 0, signature)) return table_phys;
        }
        return null;
    }

    if (sigEq4At(root, 0, .{ 'R', 'S', 'D', 'T' })) {
        const entry_bytes = length - sdt_header_size;
        const entry_count = entry_bytes / 4;
        var i: usize = 0;
        while (i < entry_count) : (i += 1) {
            const table_phys = @as(u64, readU32(root, sdt_header_size + i * 4));
            if (table_phys == 0 or table_phys >= 0x1_0000_0000) continue;
            const table = physBytes(table_phys);
            if (sigEq4At(table, 0, signature)) return table_phys;
        }
        return null;
    }

    return null;
}
