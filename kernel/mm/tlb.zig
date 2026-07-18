//! TLB shootdown for SMP. Broadcast invlpg to all online CPUs.

const std = @import("std");
const apic = @import("../arch/x86_64/apic.zig");
const paging = @import("../arch/x86_64/paging.zig");
const smp = @import("../arch/x86_64/smp.zig");
const spinlock = @import("../sync/spinlock.zig");

/// TLB shootdown IPI vector.
pub const shootdown_vector: u8 = 49;

var lock: spinlock.SpinLock = .{};
var target_cr3: u64 = 0;
var target_virt: u64 = 0;
/// Non-zero while a shootdown is in flight; handlers ack only for this generation.
var active_gen: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);
var next_gen: u64 = 1;
var ack: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);
/// Bit per CPU index: set once when that CPU acks the active generation.
var acked_mask: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);

/// Invalidate `virt` in address space `cr3` on all CPUs that may have it cached.
pub fn invalidatePage(cr3: u64, virt: u64) void {
    if (paging.readCr3() == cr3) {
        paging.invlpg(virt);
    }
    const online = smp.onlineCpuCount();
    if (online <= 1) return;

    lock.lock();
    defer lock.unlock();

    const gen = next_gen;
    next_gen +%= 1;
    if (next_gen == 0) next_gen = 1;

    target_cr3 = cr3;
    target_virt = virt;
    ack.store(0, .release);
    acked_mask.store(0, .release);
    active_gen.store(gen, .release);

    const self_id = smp.cpuId();
    var expected: usize = 0;
    var i: usize = 0;
    while (i < online) : (i += 1) {
        if (i == self_id) continue;
        const desc = smp.cpuAt(i) orelse continue;
        expected += 1;
        apic.sendIpi(desc.lapic_id, shootdown_vector);
    }

    var spins: usize = 0;
    while (ack.load(.acquire) < expected and spins < 10_000_000) : (spins += 1) {
        std.atomic.spinLoopHint();
    }

    // Retire this generation so late IPIs do not ack a future shootdown.
    _ = active_gen.cmpxchgStrong(gen, 0, .release, .monotonic);
}

pub fn shootdownIpiHandler(vector: u8) void {
    _ = vector;
    const gen = active_gen.load(.acquire);
    if (gen == 0) {
        apic.lapicEoi();
        return;
    }

    const cr3 = target_cr3;
    const virt = target_virt;
    if (active_gen.load(.acquire) != gen) {
        apic.lapicEoi();
        return;
    }

    if (paging.readCr3() == cr3) {
        paging.invlpg(virt);
    }

    if (active_gen.load(.acquire) != gen) {
        apic.lapicEoi();
        return;
    }

    const bit = @as(u64, 1) << @as(u6, @intCast(smp.cpuId()));
    const prev = acked_mask.fetchOr(bit, .acq_rel);
    if (prev & bit == 0) {
        _ = ack.fetchAdd(1, .release);
    }
    apic.lapicEoi();
}
