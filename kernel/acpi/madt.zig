const access = @import("access.zig");
const bytes = @import("common/bytes");

pub const IoApic = struct {
    id: u8,
    address: u64,
    gsi_base: u32,
};

pub const LocalApic = struct {
    /// ACPI Processor UID / processor_id.
    processor_id: u8,
    lapic_id: u8,
    /// MADT Local APIC flags bit 0 = enabled.
    enabled: bool,
};

pub const Info = struct {
    local_apic_address: u64,
    ioapics: []const IoApic,
    local_apics: []const LocalApic,
};

pub const ParseError = error{
    InvalidRsdp,
    MadtNotFound,
    TooManyIoApics,
    TooManyLocalApics,
};

const madt_header_size = access.sdt_header_size + 8;

const max_ioapics = 8;
const max_local_apics = 32;
var ioapic_storage: [max_ioapics]IoApic = undefined;
var local_apic_storage: [max_local_apics]LocalApic = undefined;

/// `rsdp_virt` is the HHDM virtual pointer from Limine (base revision >= 4).
pub fn parse(rsdp_virt: u64) ParseError!Info {
    const root_phys = access.rootTablePhys(rsdp_virt) orelse return ParseError.InvalidRsdp;

    const madt_phys = access.findTablePhys(root_phys, .{ 'A', 'P', 'I', 'C' }) orelse return ParseError.MadtNotFound;
    const madt = access.physBytes(madt_phys);
    const length = bytes.readU32Le(madt[0..8], 4);
    const madt_bytes = madt[0..length];

    var local_apic_address: u64 = bytes.readU32Le(madt_bytes, access.sdt_header_size);
    var ioapic_count: usize = 0;
    var local_apic_count: usize = 0;

    var offset: usize = madt_header_size;
    while (offset + 2 <= length) {
        const entry_type = madt_bytes[offset];
        const entry_len = madt_bytes[offset + 1];
        if (entry_len < 2) break;
        if (offset + entry_len > length) break;

        switch (entry_type) {
            0 => {
                // Processor Local APIC
                if (entry_len < 8) {
                    offset += entry_len;
                    continue;
                }
                if (local_apic_count >= max_local_apics) return ParseError.TooManyLocalApics;
                const flags = bytes.readU32Le(madt_bytes, offset + 4);
                local_apic_storage[local_apic_count] = .{
                    .processor_id = madt_bytes[offset + 2],
                    .lapic_id = madt_bytes[offset + 3],
                    .enabled = (flags & 1) != 0,
                };
                local_apic_count += 1;
            },
            1 => {
                if (entry_len < 12) {
                    offset += entry_len;
                    continue;
                }
                if (ioapic_count >= max_ioapics) return ParseError.TooManyIoApics;
                ioapic_storage[ioapic_count] = .{
                    .id = madt_bytes[offset + 2],
                    .address = bytes.readU32Le(madt_bytes, offset + 4),
                    .gsi_base = bytes.readU32Le(madt_bytes, offset + 8),
                };
                ioapic_count += 1;
            },
            5 => {
                if (entry_len < 12) {
                    offset += entry_len;
                    continue;
                }
                local_apic_address = bytes.readU64Le(madt_bytes, offset + 4);
            },
            else => {},
        }
        offset += entry_len;
    }

    return .{
        .local_apic_address = local_apic_address,
        .ioapics = ioapic_storage[0..ioapic_count],
        .local_apics = local_apic_storage[0..local_apic_count],
    };
}
