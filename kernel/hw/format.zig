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

fn memKindName(kind: abi_hw.MemKind) []const u8 {
    return switch (kind) {
        .conventional => "conventional",
        .reserved => "reserved",
        .boot_services => "boot-services",
        .runtime => "runtime",
        .mmio => "mmio",
        .acpi => "acpi",
        .unusable => "unusable",
        .unknown => "unknown",
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

/// Format a hex value with newline (sysfs attribute style), `width` nibbles.
pub fn formatHexAttr(value: u64, width: usize, dest: []u8) usize {
    const p = seq.appendHex(dest, 0, value, width);
    return seq.append(dest, p, "\n");
}

/// Format a decimal value with newline (sysfs attribute style).
pub fn formatU64Attr(value: u64, dest: []u8) usize {
    const p = seq.appendU64(dest, 0, value);
    return seq.append(dest, p, "\n");
}

/// Format PCI address as `BB:DD.F` (bus/device hex, function decimal digit).
pub fn formatPciAddr(bus: u8, device: u8, function: u8, dest: []u8) usize {
    var p = seq.appendHex(dest, 0, bus, 2);
    p = seq.append(dest, p, ":");
    p = seq.appendHex(dest, p, device, 2);
    p = seq.append(dest, p, ".");
    return seq.appendU64(dest, p, function);
}

/// Parse `BB:DD.F` into bus/device/function. Returns false on malformed input.
pub fn parsePciAddr(name: []const u8, bus: *u8, device: *u8, function: *u8) bool {
    if (name.len < 7 or name.len > 8) return false;
    if (name[2] != ':' or name[5] != '.') return false;
    bus.* = parseHexByte(name[0..2]) orelse return false;
    device.* = parseHexByte(name[3..5]) orelse return false;
    if (name.len == 7) {
        if (name[6] < '0' or name[6] > '9') return false;
        function.* = name[6] - '0';
        return true;
    }
    // Two-digit function (rare); keep simple: only single digit.
    return false;
}

fn parseHexByte(s: []const u8) ?u8 {
    if (s.len != 2) return null;
    const hi = hexNibble(s[0]) orelse return null;
    const lo = hexNibble(s[1]) orelse return null;
    return (hi << 4) | lo;
}

fn hexNibble(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return null;
}
