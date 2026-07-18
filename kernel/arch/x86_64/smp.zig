//! SMP CPU enumeration from Limine MP response (bring-up comes later).

const limine = @import("limine");
const std = @import("std");

pub const max_cpus: usize = 8;

pub const CpuDesc = struct {
    processor_id: u32 = 0,
    lapic_id: u32 = 0,
    is_bsp: bool = false,
    limine_info: ?*limine.MpInfo = null,
};

var cpus: [max_cpus]CpuDesc = [_]CpuDesc{.{}} ** max_cpus;
var available_count: usize = 1;
var bsp_lapic_id: u32 = 0;
var mp_response: ?*const limine.MpResponse = null;

/// Record CPUs from Limine MP. Safe to call with null (single-CPU fallback).
pub fn initFromLimine(response: ?*const limine.MpResponse) void {
    mp_response = response;
    if (response) |mp| {
        bsp_lapic_id = mp.bsp_lapic_id;
        const n = @min(@as(usize, @intCast(mp.cpu_count)), max_cpus);
        available_count = if (n == 0) 1 else n;
        if (mp.cpus) |list| {
            var i: usize = 0;
            while (i < available_count) : (i += 1) {
                if (list[i]) |info| {
                    cpus[i] = .{
                        .processor_id = info.processor_id,
                        .lapic_id = info.lapic_id,
                        .is_bsp = info.lapic_id == mp.bsp_lapic_id,
                        .limine_info = info,
                    };
                }
            }
        }
    } else {
        bsp_lapic_id = 0;
        available_count = 1;
        cpus[0] = .{ .is_bsp = true };
    }
}

pub fn availableCpuCount() usize {
    return available_count;
}

pub fn onlineCpuCount() usize {
    // Until AP bring-up, only the BSP is online.
    return 1;
}

pub fn bspLapicId() u32 {
    return bsp_lapic_id;
}

pub fn cpuAt(index: usize) ?CpuDesc {
    if (index >= available_count) return null;
    return cpus[index];
}

pub fn limineResponse() ?*const limine.MpResponse {
    return mp_response;
}
