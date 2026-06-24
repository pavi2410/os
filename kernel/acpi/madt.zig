const address = @import("../mm/address.zig");

pub const IoApic = struct {
    id: u8,
    address: u64,
    gsi_base: u32,
};

pub const Info = struct {
    local_apic_address: u64,
    ioapics: []const IoApic,
};

pub const ParseError = error{
    InvalidRsdp,
    MadtNotFound,
    TooManyIoApics,
};

const Rsdp = extern struct {
    signature: [8]u8,
    checksum: u8,
    oem_id: [6]u8,
    revision: u8,
    rsdt_address: u32,
    length: u32,
    xsdt_address: u64,
};

const SdtHeader = extern struct {
    signature: [4]u8,
    length: u32,
    revision: u8,
    checksum: u8,
    oem_id: [6]u8,
    oem_table_id: [8]u8,
    oem_revision: u32,
    creator_id: u32,
    creator_revision: u32,
};

const Madt = extern struct {
    header: SdtHeader,
    local_apic_address: u32,
    flags: u32,
};

const MadtEntryHeader = extern struct {
    entry_type: u8,
    length: u8,
};

const MadtIoApic = extern struct {
    header: MadtEntryHeader,
    id: u8,
    reserved: u8,
    address: u32,
    gsi_base: u32,
};

const MadtLocalApicOverride = extern struct {
    header: MadtEntryHeader,
    reserved: u16,
    address: u64,
};

const max_ioapics = 8;
var ioapic_storage: [max_ioapics]IoApic = undefined;

/// `rsdp_virt` is the HHDM virtual pointer from Limine (base revision >= 4).
pub fn parse(rsdp_virt: u64) ParseError!Info {
    const rsdp = ptrFromVirt(Rsdp, rsdp_virt);
    if (!sigEq8(&rsdp.signature, "RSD PTR ")) return ParseError.InvalidRsdp;

    const root_phys: u64 = if (rsdp.revision >= 2) rsdp.xsdt_address else rsdp.rsdt_address;
    const madt = findTable(root_phys, .{ 'A', 'P', 'I', 'C' }) orelse return ParseError.MadtNotFound;

    var local_apic_address: u64 = madt.local_apic_address;
    var ioapic_count: usize = 0;

    const madt_bytes: [*]const u8 = @ptrCast(madt);
    var offset: usize = @sizeOf(Madt);
    while (offset + @sizeOf(MadtEntryHeader) <= madt.header.length) {
        const entry = @as(*const MadtEntryHeader, @ptrCast(@alignCast(madt_bytes + offset)));
        if (entry.length < @sizeOf(MadtEntryHeader)) break;
        if (offset + entry.length > madt.header.length) break;

        switch (entry.entry_type) {
            1 => {
                const ioapic = @as(*const MadtIoApic, @ptrCast(@alignCast(madt_bytes + offset)));
                if (ioapic_count >= max_ioapics) return ParseError.TooManyIoApics;
                ioapic_storage[ioapic_count] = .{
                    .id = ioapic.id,
                    .address = ioapic.address,
                    .gsi_base = ioapic.gsi_base,
                };
                ioapic_count += 1;
            },
            5 => {
                const override = @as(*const MadtLocalApicOverride, @ptrCast(@alignCast(madt_bytes + offset)));
                local_apic_address = override.address;
            },
            else => {},
        }
        offset += entry.length;
    }

    return .{
        .local_apic_address = local_apic_address,
        .ioapics = ioapic_storage[0..ioapic_count],
    };
}

fn findTable(root_phys: u64, signature: [4]u8) ?*const Madt {
    const root = ptrFromPhys(SdtHeader, root_phys);
    if (root.length < @sizeOf(SdtHeader)) return null;

    if (sigEq4(&root.signature, .{ 'X', 'S', 'D', 'T' })) {
        const xsdt_bytes: [*]const u8 = @ptrCast(root);
        const entry_bytes = root.length - @sizeOf(SdtHeader);
        const entry_count = entry_bytes / 8;
        var i: usize = 0;
        while (i < entry_count) : (i += 1) {
            const table_phys = @as(*const u64, @ptrCast(@alignCast(xsdt_bytes + @sizeOf(SdtHeader) + i * 8))).*;
            const table = ptrFromPhys(SdtHeader, table_phys);
            if (sigEq4(&table.signature, signature)) {
                return @ptrCast(@alignCast(table));
            }
        }
        return null;
    }

    if (sigEq4(&root.signature, .{ 'R', 'S', 'D', 'T' })) {
        const rsdt_bytes: [*]const u8 = @ptrCast(root);
        const entry_bytes = root.length - @sizeOf(SdtHeader);
        const entry_count = entry_bytes / 4;
        var i: usize = 0;
        while (i < entry_count) : (i += 1) {
            const table_phys = @as(u64, @as(*const u32, @ptrCast(@alignCast(rsdt_bytes + @sizeOf(SdtHeader) + i * 4))).*);
            const table = ptrFromPhys(SdtHeader, table_phys);
            if (sigEq4(&table.signature, signature)) {
                return @ptrCast(@alignCast(table));
            }
        }
        return null;
    }

    return null;
}

fn ptrFromPhys(comptime T: type, phys: u64) *const T {
    return @ptrCast(@alignCast(@as(*const anyopaque, @ptrFromInt(address.physToVirt(phys)))));
}

fn ptrFromVirt(comptime T: type, virt: u64) *const T {
    return @ptrCast(@alignCast(@as(*const anyopaque, @ptrFromInt(virt))));
}

fn sigEq4(sig: *const [4]u8, expected: [4]u8) bool {
    return sig[0] == expected[0] and sig[1] == expected[1] and
        sig[2] == expected[2] and sig[3] == expected[3];
}

fn sigEq8(sig: *const [8]u8, expected: []const u8) bool {
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        if (sig[i] != expected[i]) return false;
    }
    return true;
}
