//! Pure text formatters for procfs/sysfs (host-testable).
//!
//! `/proc/cpuinfo` follows Linux key names loosely; `apic_id` and `ioapic_count`
//! are intentional extras for this OS.

const abi_hw = @import("abi_hw");
const seq = @import("../fs/seq.zig");

pub const CpuInfo = abi_hw.CpuInfo;
pub const MemRegionInfo = abi_hw.MemRegionInfo;

fn zstr(buf: []const u8) []const u8 {
    var i: usize = 0;
    while (i < buf.len and buf[i] != 0) : (i += 1) {}
    return buf[0..i];
}

fn memKindName(kind: u32) []const u8 {
    return switch (kind) {
        abi_hw.MEM_CONVENTIONAL => "conventional",
        abi_hw.MEM_RESERVED => "reserved",
        abi_hw.MEM_BOOT_SERVICES => "boot-services",
        abi_hw.MEM_RUNTIME => "runtime",
        abi_hw.MEM_MMIO => "mmio",
        abi_hw.MEM_ACPI => "acpi",
        abi_hw.MEM_UNUSABLE => "unusable",
        else => "unknown",
    };
}

fn appendKeyLine(dest: []u8, pos: usize, key: []const u8, value: []const u8) usize {
    var p = seq.append(dest, pos, key);
    p = seq.append(dest, p, "\t: ");
    p = seq.append(dest, p, value);
    return seq.append(dest, p, "\n");
}

fn appendKeyU64(dest: []u8, pos: usize, key: []const u8, value: u64) usize {
    var p = seq.append(dest, pos, key);
    p = seq.append(dest, p, "\t: ");
    p = seq.appendU64(dest, p, value);
    return seq.append(dest, p, "\n");
}

/// Format `info` into `/proc/cpuinfo` text. Returns bytes written.
pub fn formatCpuinfo(info: *const CpuInfo, dest: []u8) usize {
    var p: usize = 0;
    p = appendKeyLine(dest, p, "vendor_id", zstr(info.vendor[0..]));
    p = appendKeyU64(dest, p, "cpu family", info.family);
    p = appendKeyU64(dest, p, "model", info.model);
    p = appendKeyLine(dest, p, "model name", zstr(info.brand[0..]));
    p = appendKeyU64(dest, p, "stepping", info.stepping);
    p = appendKeyU64(dest, p, "apic_id", info.apic_id);
    p = appendKeyU64(dest, p, "cpu cores", info.logical_cpus);
    p = appendKeyU64(dest, p, "ioapic_count", info.ioapic_count);
    return p;
}

/// Format memory regions as `/proc/iomem` lines: `start-end : type`.
pub fn formatIomem(regions: []const MemRegionInfo, dest: []u8) usize {
    var p: usize = 0;
    for (regions) |r| {
        const end = if (r.length > 0) r.start + r.length - 1 else r.start;
        p = seq.appendHex(dest, p, r.start, 16);
        p = seq.append(dest, p, "-");
        p = seq.appendHex(dest, p, end, 16);
        p = seq.append(dest, p, " : ");
        p = seq.append(dest, p, memKindName(r.kind));
        p = seq.append(dest, p, "\n");
    }
    return p;
}
