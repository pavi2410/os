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

pub const SchedulerError = error{
    OutOfMemory,
};

/// Timer ticks between preemption requests (~100 ms at 100 Hz LAPIC).
/// Fixed round-robin slice; not CFS. Tunable at compile time.
pub const time_slice_ticks: u64 = 10;

const ReadyQueue = ready_queue.ReadyQueue(thread.Thread);

/// Non-preemptible regions (uniprocessor):
/// - Heap freelist (`kmalloc`/`kfree` hold `preempt.disable`)
/// - Ready-queue mutations and voluntary `yield` entry
/// - TTY ctrl-c poll/send inside `yield`
/// Syscalls also run with IF cleared (SFMASK), so they are non-preemptible.
///
/// `preempt` count blocks *involuntary* preemption only (`scheduleFromIrq` /
/// `yieldIfRequested`). Explicit `yield` still switches.
pub const Scheduler = struct {
    bootstrap: thread.Thread = undefined,
    idle_thread: *thread.Thread = undefined,
    ready_queue: ReadyQueue = .{},
    preempt_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    ticks: u64 = 0,
};
var default_state: Scheduler = .{};
var state: *Scheduler = &default_state;

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

/// True when involuntary preemption is allowed.
pub fn canPreempt() bool {
    return preempt.canPreempt();
}

pub fn init() void {
    state.* = .{};
    state.bootstrap = .{
        .id = 0,
        .name = "bootstrap",
        .stack = undefined,
        .stack_size = 0,
        .context = undefined,
        .state = .running,
    };
    thread.setCurrent(&state.bootstrap);

    state.idle_thread = thread.create(idleEntry, "idle", thread.default_stack_size) catch {
        hal.console.println("idle thread create failed", .{});
        cpu.haltForever();
    };

    thread.setExitHandler(exitCurrent);
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
    preemptDisable();
    t.state = .ready;
    state.ready_queue.push(t);
    preemptEnable();
    return t;
}

pub fn onTimerTick() void {
    state.ticks += 1;
    if (state.ticks % time_slice_ticks == 0) {
        state.preempt_requested.store(true, .monotonic);
    }
}

pub fn yieldIfRequested() void {
    // Leave the flag set while preemption is disabled (sticky across critical sections).
    if (!canPreempt()) return;
    if (state.preempt_requested.swap(false, .monotonic)) {
        yield();
    }
}

/// Involuntary preemption from the timer IRQ (after EOI).
/// Leaves the full IRQ frame on the preempted thread's kernel stack; resume
/// returns into `irq_stub` → `iretq`. No TTY side effects; signals applied on resume.
pub fn scheduleFromIrq() void {
    if (!canPreempt()) return;
    if (!state.preempt_requested.swap(false, .monotonic)) return;

    const self = thread.currentThread() orelse return;
    if (self.state != .dead and self != state.idle_thread) {
        self.state = .ready;
        state.ready_queue.push(self);
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
    // Block IRQ-driven switch while mutating TTY/scheduler state and switching.
    preemptDisable();
    defer preemptEnable();

    tty.get().pollCtrlC();
    if (tty.get().takePendingCtrlC()) |pid| {
        _ = signal.send(pid, abi_signal.SIGINT);
    }
    const self = thread.currentThread() orelse return;
    if (self.state != .dead and self != state.idle_thread) {
        self.state = .ready;
        state.ready_queue.push(self);
    }
    schedule();
}

pub fn start() noreturn {
    hal.console.println("\n--- Scheduler ---", .{});

    init_launch.launch();

    hal.console.println("Enabling interrupts", .{});
    // Prevent timer scheduleFromIrq from nesting inside the first scheduleSwitch.
    preemptDisable();
    cpu.sti();
    schedule();
    preemptEnable();
    cpu.haltForever();
}

fn schedule() void {
    scheduleSwitch();
    if (process.currentProcess()) |proc| signal.tryApply(proc);
}

/// Context switch only — used by IRQ path (no signal delivery).
fn scheduleSwitch() void {
    const self = thread.currentThread() orelse return;
    const next = state.ready_queue.pop() orelse state.idle_thread;
    if (next == self) return;
    self.switchTo(next);
}

fn exitCurrent() noreturn {
    yield();
    while (true) cpu.hlt();
}

fn idleEntry() callconv(.{ .x86_64_sysv = .{} }) noreturn {
    while (true) {
        yieldIfRequested();
        cpu.hlt();
    }
}

fn demoThreadA() callconv(.{ .x86_64_sysv = .{} }) noreturn {
    while (true) {
        hal.console.writeAll("A");
        yieldIfRequested();
    }
}

fn demoThreadB() callconv(.{ .x86_64_sysv = .{} }) noreturn {
    while (true) {
        hal.console.writeAll("B");
        yieldIfRequested();
    }
}
