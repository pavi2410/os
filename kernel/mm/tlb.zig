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
var ack: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);

/// Invalidate `virt` in address space `cr3` on all CPUs that may have it cached.
pub fn invalidatePage(cr3: u64, virt: u64) void {
    if (paging.readCr3() == cr3) {
        paging.invlpg(virt);
    }
    const online = smp.onlineCpuCount();
    if (online <= 1) return;

    lock.lock();
    defer lock.unlock();

    target_cr3 = cr3;
    target_virt = virt;
    ack.store(0, .release);

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
}

pub fn shootdownIpiHandler(vector: u8) void {
    _ = vector;
    const cr3 = target_cr3;
    const virt = target_virt;
    if (paging.readCr3() == cr3) {
        paging.invlpg(virt);
    }
    _ = ack.fetchAdd(1, .release);
    apic.lapicEoi();
}
