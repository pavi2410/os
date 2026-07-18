const cpu = @import("../arch/x86_64/cpu.zig");
const hal = @import("../hal.zig");
const abi_signal = @import("abi_signal");
const init_launch = @import("init_launch.zig");
const preempt = @import("preempt.zig");
const process = @import("process.zig");
const ready_queue = @import("ready_queue.zig");
const signal = @import("signal.zig");
const thread = @import("thread.zig");
const proc_types = @import("types.zig");
const tty = @import("../drivers/tty.zig");
const std = @import("std");
const smp = @import("../arch/x86_64/smp.zig");
const spinlock = @import("../sync/spinlock.zig");
const apic = @import("../arch/x86_64/apic.zig");

pub const SchedulerError = error{
    OutOfMemory,
};

/// Timer ticks between preemption requests (~100 ms at 100 Hz LAPIC).
pub const time_slice_ticks: u64 = 10;

/// Reschedule IPI vector (after timer IRQ range 32–47).
pub const reschedule_vector: u8 = 48;

const ReadyQueue = ready_queue.ReadyQueue(thread.Thread);

const PerCpu = struct {
    ready_queue: ReadyQueue = .{},
    lock: spinlock.SpinLock = .{},
    idle_thread: ?*thread.Thread = null,
    preempt_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    ticks: u64 = 0,
};

pub const Scheduler = struct {
    bootstrap: thread.Thread = undefined,
    /// Round-robin next CPU for spawn.
    next_cpu: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
};
var default_state: Scheduler = .{};
var state: *Scheduler = &default_state;
var per_cpu: [smp.max_cpus]PerCpu = [_]PerCpu{.{}} ** smp.max_cpus;

pub fn install(next: *Scheduler) void {
    state = next;
    state.* = .{};
}

pub fn preemptDisable() void {
    preempt.disable();
}

pub fn preemptEnable() void {
    preempt.enable();
}

pub fn preemptCount() usize {
    return preempt.count();
}

pub fn canPreempt() bool {
    return preempt.canPreempt();
}

fn cpuSched(cpu_index: u32) *PerCpu {
    return &per_cpu[cpu_index];
}

fn thisSched() *PerCpu {
    return cpuSched(smp.cpuId());
}

pub fn init() void {
    state.* = .{};
    per_cpu = [_]PerCpu{.{}} ** smp.max_cpus;

    state.bootstrap = .{
        .id = 0,
        .name = "bootstrap",
        .stack = undefined,
        .stack_size = 0,
        .context = undefined,
        .state = .running,
    };
    thread.setCurrent(&state.bootstrap);

    const idle = thread.create(idleEntry, "idle", thread.default_stack_size) catch {
        hal.console.println("idle thread create failed", .{});
        cpu.haltForever();
    };
    thisSched().idle_thread = idle;

    thread.setExitHandler(exitCurrent);
}

/// Create per-CPU idle threads for APs and park them in the scheduler.
pub fn prepareApIdle(cpu_index: u32) void {
    const name = if (cpu_index == 1) "idle-1" else if (cpu_index == 2) "idle-2" else if (cpu_index == 3) "idle-3" else "idle-n";
    const idle = thread.create(idleEntry, name, thread.default_stack_size) catch {
        return;
    };
    cpuSched(cpu_index).idle_thread = idle;
}

pub fn spawn(entry: thread.EntryFn, name: []const u8) SchedulerError!void {
    _ = try spawnWithProcess(entry, name, null);
}

pub fn spawnWithProcess(
    entry: thread.EntryFn,
    name: []const u8,
    proc: ?proc_types.Id,
) SchedulerError!*thread.Thread {
    const t = thread.create(entry, name, thread.default_stack_size) catch return SchedulerError.OutOfMemory;
    t.process_id = proc;

    // Run new threads on the spawning CPU. Cross-CPU migration is via IPI wake
    // when we explicitly choose a remote CPU later; pinning avoids shipping
    // early init/shell to an AP before userspace is proven there.
    const target: u32 = smp.cpuId();

    enqueueOn(target, t);
    return t;
}

fn enqueueOn(cpu_index: u32, t: *thread.Thread) void {
    const sched = cpuSched(cpu_index);
    sched.lock.lock();
    t.state = .ready;
    sched.ready_queue.push(t);
    sched.lock.unlock();
}

pub fn onTimerTick() void {
    const sched = thisSched();
    sched.ticks += 1;
    if (sched.ticks % time_slice_ticks == 0) {
        sched.preempt_requested.store(true, .monotonic);
    }
}

pub fn yieldIfRequested() void {
    if (!canPreempt()) return;
    if (thisSched().preempt_requested.swap(false, .monotonic)) {
        yield();
    }
}

pub fn scheduleFromIrq() void {
    if (!canPreempt()) return;
    if (!thisSched().preempt_requested.swap(false, .monotonic)) return;

    const self = thread.currentThread() orelse return;
    const sched = thisSched();
    if (self.state != .dead and self != sched.idle_thread) {
        sched.lock.lock();
        self.state = .ready;
        sched.ready_queue.push(self);
        sched.lock.unlock();
    }
    scheduleSwitch();
    if (process.currentProcess()) |proc| signal.tryApply(proc);
}

pub fn cooperativePoll() void {
    cpu.sti();
    if (process.currentProcess()) |proc| signal.tryApply(proc);
    yieldIfRequested();
    yield();
    cpu.cli();
}

pub fn yield() void {
    preemptDisable();
    defer preemptEnable();

    tty.get().pollCtrlC();
    if (tty.get().takePendingCtrlC()) |pid| {
        _ = signal.send(pid, abi_signal.SIGINT);
    }
    const self = thread.currentThread() orelse return;
    const sched = thisSched();
    if (self.state != .dead and self != sched.idle_thread) {
        sched.lock.lock();
        self.state = .ready;
        sched.ready_queue.push(self);
        sched.lock.unlock();
    }
    schedule();
}

pub fn start() noreturn {
    hal.console.println("\n--- Scheduler ---", .{});

    init_launch.launch();

    hal.console.println("Enabling interrupts", .{});
    preemptDisable();
    cpu.sti();
    schedule();
    preemptEnable();
    cpu.haltForever();
}

/// AP entry into the scheduler after hardware bring-up.
pub fn apMain() noreturn {
    const id = smp.cpuId();
    if (thisSched().idle_thread == null) {
        prepareApIdle(id);
    }
    const idle = thisSched().idle_thread orelse {
        while (true) cpu.hlt();
    };
    idle.state = .running;
    thread.setCurrent(idle);
    cpu.sti();
    while (true) {
        yieldIfRequested();
        // Pull work if any; otherwise hlt.
        const sched = thisSched();
        sched.lock.lock();
        const has_work = !sched.ready_queue.isEmpty();
        sched.lock.unlock();
        if (has_work) {
            schedule();
        } else {
            smp.thisCpu().idle_count += 1;
            cpu.hlt();
        }
    }
}

fn schedule() void {
    scheduleSwitch();
    if (process.currentProcess()) |proc| signal.tryApply(proc);
}

fn scheduleSwitch() void {
    const self = thread.currentThread() orelse return;
    const sched = thisSched();
    sched.lock.lock();
    const next = sched.ready_queue.pop() orelse sched.idle_thread orelse {
        sched.lock.unlock();
        return;
    };
    sched.lock.unlock();
    if (next == self) return;
    smp.thisCpu().work_count += 1;
    self.switchTo(next);
}

fn exitCurrent() noreturn {
    yield();
    while (true) cpu.hlt();
}

fn idleEntry() callconv(.{ .x86_64_sysv = .{} }) noreturn {
    while (true) {
        yieldIfRequested();
        smp.thisCpu().idle_count += 1;
        cpu.hlt();
    }
}

pub fn requestReschedule(cpu_index: u32) void {
    if (cpu_index == smp.cpuId()) {
        thisSched().preempt_requested.store(true, .monotonic);
        return;
    }
    const desc = smp.cpuAt(cpu_index) orelse return;
    cpuSched(cpu_index).preempt_requested.store(true, .monotonic);
    apic.sendIpi(desc.lapic_id, reschedule_vector);
}

pub fn rescheduleIpiHandler(vector: u8) void {
    _ = vector;
    apic.lapicEoi();
    scheduleFromIrq();
}
