const abi_hw = @import("abi_hw");
const syscall = @import("syscall.zig");
const pci_class = @import("pci_class.zig");

pub const CpuInfo = abi_hw.CpuInfo;
pub const PciDeviceInfo = abi_hw.PciDeviceInfo;
pub const BlockDeviceInfo = abi_hw.BlockDeviceInfo;
pub const MemRegionInfo = abi_hw.MemRegionInfo;

pub const MEM_CONVENTIONAL = abi_hw.MEM_CONVENTIONAL;
pub const MEM_RESERVED = abi_hw.MEM_RESERVED;
pub const MEM_BOOT_SERVICES = abi_hw.MEM_BOOT_SERVICES;
pub const MEM_RUNTIME = abi_hw.MEM_RUNTIME;
pub const MEM_MMIO = abi_hw.MEM_MMIO;
pub const MEM_ACPI = abi_hw.MEM_ACPI;
pub const MEM_UNUSABLE = abi_hw.MEM_UNUSABLE;
pub const MEM_UNKNOWN = abi_hw.MEM_UNKNOWN;

pub fn getcpuinfo(out: *CpuInfo) isize {
    return syscall.getcpuinfo(out);
}

pub fn getpcidevices(buf: [*]PciDeviceInfo, max: usize) isize {
    return syscall.getpcidevices(buf, max);
}

pub fn getblockdevices(buf: [*]BlockDeviceInfo, max: usize) isize {
    return syscall.getblockdevices(buf, max);
}

pub fn getmemregions(buf: [*]MemRegionInfo, max: usize) isize {
    return syscall.getmemregions(buf, max);
}

pub fn zstr(buf: []const u8) []const u8 {
    var i: usize = 0;
    while (i < buf.len and buf[i] != 0) : (i += 1) {}
    return buf[0..i];
}

pub fn memKindName(kind: u32) []const u8 {
    return switch (kind) {
        MEM_CONVENTIONAL => "conventional",
        MEM_RESERVED => "reserved",
        MEM_BOOT_SERVICES => "boot-services",
        MEM_RUNTIME => "runtime",
        MEM_MMIO => "mmio",
        MEM_ACPI => "acpi",
        MEM_UNUSABLE => "unusable",
        else => "unknown",
    };
}

pub const PciClass = pci_class.PciClass;
pub const StorageSubclass = pci_class.StorageSubclass;

pub fn pciClassName(class_code: u8, subclass: u8) []const u8 {
    return pci_class.className(class_code, subclass);
}

pub fn formatHex16(value: u16, out: []u8) []const u8 {
    const hex = "0123456789abcdef";
    if (out.len < 4) return "????";
    out[0] = hex[(value >> 12) & 0xF];
    out[1] = hex[(value >> 8) & 0xF];
    out[2] = hex[(value >> 4) & 0xF];
    out[3] = hex[value & 0xF];
    return out[0..4];
}

pub fn formatHexByte(value: u8, out: []u8) []const u8 {
    const hex = "0123456789abcdef";
    if (out.len < 2) return "??";
    out[0] = hex[value >> 4];
    out[1] = hex[value & 0xF];
    return out[0..2];
}

pub fn formatHexByte2(value: u8, out: []u8) []const u8 {
    const hex = "0123456789abcdef";
    if (out.len < 2) return "??";
    out[0] = hex[(value >> 4) & 0xF];
    out[1] = hex[value & 0xF];
    return out[0..2];
}

pub fn formatHex64(value: u64, out: []u8) []const u8 {
    const hex = "0123456789abcdef";
    if (out.len < 16) return "????";
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        const shift: u6 = @intCast(60 - i * 4);
        out[i] = hex[(value >> shift) & 0xF];
    }
    return out[0..16];
}

pub fn formatSize(bytes: u64, out: []u8) []const u8 {
    if (bytes >= 1024 * 1024 * 1024) {
        const gib = bytes / (1024 * 1024 * 1024);
        const rem = (bytes % (1024 * 1024 * 1024)) * 10 / (1024 * 1024 * 1024);
        return formatDecimalPair(gib, rem, "G", out);
    }
    if (bytes >= 1024 * 1024) {
        const mib = bytes / (1024 * 1024);
        const rem = (bytes % (1024 * 1024)) * 10 / (1024 * 1024);
        return formatDecimalPair(mib, rem, "M", out);
    }
    if (bytes >= 1024) {
        const kib = bytes / 1024;
        const rem = (bytes % 1024) * 10 / 1024;
        return formatDecimalPair(kib, rem, "K", out);
    }
    return formatDecimalPair(bytes, 0, "B", out);
}

fn formatDecimalPair(whole: u64, tenth: u64, suffix: []const u8, out: []u8) []const u8 {
    if (out.len < 2 + suffix.len) return "?";

    var len: usize = 0;
    var n = whole;
    var digits: [20]u8 = undefined;
    var dcount: usize = 0;
    if (n == 0) {
        digits[0] = '0';
        dcount = 1;
    } else {
        while (n > 0) : (n /= 10) {
            digits[dcount] = @truncate((n % 10) + '0');
            dcount += 1;
        }
    }
    while (dcount > 0) : (dcount -= 1) {
        if (len >= out.len - suffix.len) return "?";
        out[len] = digits[dcount - 1];
        len += 1;
    }
    if (tenth > 0) {
        if (len + 2 + suffix.len > out.len) return "?";
        out[len] = '.';
        len += 1;
        out[len] = @truncate(tenth + '0');
        len += 1;
    }
    if (len + suffix.len > out.len) return "?";
    @memcpy(out[len .. len + suffix.len], suffix);
    len += suffix.len;
    return out[0..len];
}
