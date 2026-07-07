const abi_hw = @import("abi_hw");
const apic = @import("../arch/x86_64/apic.zig");
const cpuid = @import("../arch/x86_64/cpuid.zig");
const block = @import("../drivers/block.zig");
const memory_map = @import("../mm/memory_map.zig");
const pci = @import("../drivers/pci.zig");
const std = @import("std");

comptime {
    if (@offsetOf(abi_hw.CpuInfo, "vendor") != 0) @compileError("CpuInfo.vendor must be at offset 0");
    if (@offsetOf(abi_hw.CpuInfo, "logical_cpus") != 80) @compileError("CpuInfo.logical_cpus must be at offset 80");
}

pub const CpuInfo = abi_hw.CpuInfo;
pub const PciDeviceInfo = abi_hw.PciDeviceInfo;
pub const BlockDeviceInfo = abi_hw.BlockDeviceInfo;
pub const MemRegionInfo = abi_hw.MemRegionInfo;

pub fn fillCpuInfo(out: *CpuInfo) void {
    out.* = std.mem.zeroes(CpuInfo);

    const basic = cpuid.leaf(1, 0);
    const fms = cpuid.familyModelStepping(basic.eax);
    out.logical_cpus = @max(@as(u32, 1), (basic.ebx >> 16) & 0xFF);
    out.ioapic_count = @intCast(apic.ioApicCount());
    out.family = fms.family;
    out.model = fms.model;
    out.stepping = fms.stepping;
    out.apic_id = @truncate(basic.ebx >> 24);

    var vendor_raw: [12]u8 = undefined;
    cpuid.vendorString(&vendor_raw);
    @memcpy(out.vendor[0..12], &vendor_raw);
    var brand_raw: [48]u8 = undefined;
    cpuid.brandString(&brand_raw);
    trimTrailingSpaces(&brand_raw);
    const brand_len = @min(brandRawLen(&brand_raw), out.brand.len - 1);
    @memcpy(out.brand[0..brand_len], brand_raw[0..brand_len]);
}

pub fn fillPciDevices(buf: []PciDeviceInfo) usize {
    const list = pci.devices();
    const count = @min(buf.len, list.len);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const dev = list[i];
        buf[i] = .{
            .vendor_id = dev.vendor_id,
            .device_id = dev.device_id,
            .segment = dev.segment,
            .bus = dev.bus,
            .device = dev.device,
            .function = dev.function,
            .class_code = dev.class_code,
            .subclass = dev.subclass,
            .prog_if = dev.prog_if,
            ._pad = 0,
        };
    }
    return count;
}

pub fn fillBlockDevices(buf: []BlockDeviceInfo) usize {
    const dev = block.default() orelse return 0;
    if (!dev.isReady()) return 0;
    if (buf.len == 0) return 0;

    @memset(buf[0].name[0..], 0);
    const name = dev.name;
    const copy_len = @min(name.len, buf[0].name.len - 1);
    @memcpy(buf[0].name[0..copy_len], name[0..copy_len]);
    buf[0].sector_size = @intCast(dev.sectorSize());
    buf[0].capacity_sectors = dev.capacity();
    return 1;
}

pub fn fillMemRegions(buf: []MemRegionInfo) usize {
    const list = memory_map.regionsSlice();
    const count = @min(buf.len, list.len);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const region = list[i];
        buf[i] = .{
            .start = region.start,
            .length = region.end - region.start,
            .kind = mapMemKind(region.kind),
        };
    }
    return count;
}

fn brandRawLen(raw: *const [48]u8) usize {
    var len: usize = 48;
    while (len > 0 and raw[len - 1] == 0) len -= 1;
    return len;
}

fn trimTrailingSpaces(buf: *[48]u8) void {
    var len = brandRawLen(buf);
    while (len > 0 and buf[len - 1] == ' ') len -= 1;
    if (len < 48) @memset(buf[len..], 0);
}

fn mapMemKind(kind: memory_map.RegionKind) u32 {
    return switch (kind) {
        .conventional => abi_hw.MEM_CONVENTIONAL,
        .reserved => abi_hw.MEM_RESERVED,
        .boot_services => abi_hw.MEM_BOOT_SERVICES,
        .runtime => abi_hw.MEM_RUNTIME,
        .mmio => abi_hw.MEM_MMIO,
        .acpi => abi_hw.MEM_ACPI,
        .unusable => abi_hw.MEM_UNUSABLE,
        .unknown => abi_hw.MEM_UNKNOWN,
    };
}
