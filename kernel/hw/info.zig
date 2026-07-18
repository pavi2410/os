const abi_hw = @import("abi_hw");
const apic = @import("../arch/x86_64/apic.zig");
const cpuid = @import("../arch/x86_64/cpuid.zig");
const memory_map = @import("../mm/memory_map.zig");
const smp = @import("../arch/x86_64/smp.zig");
const std = @import("std");

pub const CpuInfo = abi_hw.CpuInfo;
pub const MemRegionInfo = abi_hw.MemRegionInfo;

pub fn fillCpuInfo(out: *CpuInfo) void {
    out.* = std.mem.zeroes(CpuInfo);

    const basic = cpuid.leaf(1, 0);
    const fms = cpuid.familyModelStepping(basic.eax);
    out.logical_cpus = @max(@as(u32, 1), @as(u32, @intCast(smp.onlineCpuCount())));
    out.ioapic_count = @intCast(apic.ioApicCount());
    out.family = fms.family;
    out.model = fms.model;
    out.stepping = fms.stepping;
    out.apic_id = @truncate(smp.thisCpu().lapic_id);

    var vendor_raw: [12]u8 = undefined;
    cpuid.vendorString(&vendor_raw);
    @memcpy(out.vendor[0..12], &vendor_raw);
    var brand_raw: [48]u8 = undefined;
    cpuid.brandString(&brand_raw);
    trimTrailingSpaces(&brand_raw);
    const brand_len = @min(brandRawLen(&brand_raw), out.brand.len - 1);
    @memcpy(out.brand[0..brand_len], brand_raw[0..brand_len]);
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
            .kind = region.kind,
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
