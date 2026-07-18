//! SMP: Limine MP enumeration, per-CPU locals (GS), and AP bring-up.

const std = @import("std");
const limine = @import("limine");
const cpu = @import("cpu.zig");
const gdt = @import("gdt.zig");
const idt = @import("idt.zig");
const apic = @import("apic.zig");
const timer = @import("timer.zig");
const hal = @import("../../hal.zig");

pub const max_cpus: usize = 8;

/// IA32_GS_BASE — CpuLocal pointer for this CPU.
const IA32_GS_BASE: u32 = 0xC0000101;

pub const CpuDesc = struct {
    processor_id: u32 = 0,
    lapic_id: u32 = 0,
    is_bsp: bool = false,
    limine_info: ?*limine.MpInfo = null,
};

/// Per-CPU state. `kernel_rsp0` is at offset 0 so the syscall stub can use `%gs:0`.
/// Large/aligned members live in parallel arrays so Zig does not reorder this struct.
pub const CpuLocal = extern struct {
    kernel_rsp0: u64 = 0,
    cpu_id: u32 = 0,
    lapic_id: u32 = 0,
    online: u8 = 0,
    _pad0: [7]u8 = .{0} ** 7,
    /// `*thread.Thread` stored as opaque to avoid import cycles.
    current: ?*anyopaque = null,
    idle: ?*anyopaque = null,
    work_count: u64 = 0,
    idle_count: u64 = 0,
};

pub const kernel_rsp0_offset = @offsetOf(CpuLocal, "kernel_rsp0");
comptime {
    if (kernel_rsp0_offset != 0) @compileError("CpuLocal.kernel_rsp0 must be at offset 0");
}

var cpu_locals: [max_cpus]CpuLocal = [_]CpuLocal{.{}} ** max_cpus;
var cpu_tss: [max_cpus]gdt.Tss = [_]gdt.Tss{.{}} ** max_cpus;
var cpu_gdt: [max_cpus][7]gdt.GdtEntry = undefined;
var cpu_ist: [max_cpus][16 * 1024]u8 align(16) = undefined;
var cpus: [max_cpus]CpuDesc = [_]CpuDesc{.{}} ** max_cpus;
var available_count: usize = 1;
var online_count: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);
var bsp_lapic_id: u32 = 0;
var mp_response: ?*const limine.MpResponse = null;
var bsp_ready: bool = false;

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

/// Initialize BSP CpuLocal and load GS. Call after GDT is up.
pub fn initBsp() void {
    const local = &cpu_locals[0];
    local.* = .{};
    local.cpu_id = 0;
    local.lapic_id = bsp_lapic_id;
    local.online = 1;
    setupCpuGdt(0);
    setGsBase(local);
    _ = online_count.fetchAdd(1, .release);
    bsp_ready = true;
    hal.console.println("cpu0 local ready (GS)", .{});
}

pub fn availableCpuCount() usize {
    return available_count;
}

pub fn onlineCpuCount() usize {
    return online_count.load(.acquire);
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

pub fn cpuLocal(index: usize) *CpuLocal {
    return &cpu_locals[index];
}

pub fn thisCpu() *CpuLocal {
    if (!bsp_ready) return &cpu_locals[0];
    return @ptrFromInt(cpu.rdmsr(IA32_GS_BASE));
}

pub fn cpuId() u32 {
    return thisCpu().cpu_id;
}

pub fn setKernelStack(stack_top: u64) void {
    const local = thisCpu();
    local.kernel_rsp0 = stack_top;
    cpu_tss[local.cpu_id].rsp0 = stack_top;
    gdt.setKernelStackExport(stack_top);
}

fn setGsBase(local: *CpuLocal) void {
    cpu.wrmsr(IA32_GS_BASE, @intFromPtr(local));
}

fn setupCpuGdt(index: usize) void {
    const tss = &cpu_tss[index];
    tss.* = .{};
    const ist = &cpu_ist[index];
    const ist_top = (@intFromPtr(ist) + ist.len) & ~@as(u64, 15);
    tss.ist1 = ist_top;
    const entries = &cpu_gdt[index];
    gdt.fillStandardEntries(entries);
    gdt.installTssDescriptor(entries, tss);
    gdt.loadFrom(entries);
}

/// Release parked APs via Limine `goto_address`. Call after scheduler + timer on BSP.
pub fn startAps() void {
    const scheduler = @import("../../proc/scheduler.zig");
    var i: usize = 0;
    while (i < available_count) : (i += 1) {
        if (cpus[i].is_bsp) continue;
        scheduler.prepareApIdle(@intCast(i));
    }

    i = 0;
    while (i < available_count) : (i += 1) {
        const desc = cpus[i];
        if (desc.is_bsp) continue;
        const info = desc.limine_info orelse continue;
        const local = &cpu_locals[i];
        local.* = .{};
        local.cpu_id = @intCast(i);
        local.lapic_id = desc.lapic_id;
        info.extra_argument = i;
        @atomicStore(
            ?*const fn (*limine.MpInfo) callconv(.c) noreturn,
            &info.goto_address,
            &apEntry,
            .release,
        );
    }

    const want = available_count;
    var spins: usize = 0;
    while (onlineCpuCount() < want and spins < 10_000_000) : (spins += 1) {
        std.atomic.spinLoopHint();
    }
    hal.console.println("CPUs online: {d}", .{onlineCpuCount()});
}

fn apEntry(info: *limine.MpInfo) callconv(.c) noreturn {
    const index: usize = @intCast(info.extra_argument);
    const local = &cpu_locals[index];
    setupCpuGdt(index);
    idt.load();
    setGsBase(local);
    apic.enableOnAp();
    timer.startOnAp();

    local.online = 1;
    _ = online_count.fetchAdd(1, .release);
    // Serial is racy across CPUs; keep message short.
    hal.console.println("CPU {d} online (LAPIC id {d})", .{ local.cpu_id, local.lapic_id });

    const scheduler = @import("../../proc/scheduler.zig");
    scheduler.apMain();
}
