const cpu = @import("../arch/x86_64/cpu.zig");
const hal = @import("../hal.zig");
const heap = @import("../mm/heap.zig");
const abi_signal = @import("abi_signal");
const init_shell = @import("init_shell.zig");
const process = @import("process.zig");
const signal = @import("signal.zig");
const thread = @import("thread.zig");
const tty = @import("../drivers/tty.zig");
const std = @import("std");

pub const SchedulerError = error{
    OutOfMemory,
};

/// Timer ticks between preemption requests.
/// Threads must call `yieldIfRequested()`; true IRQ-level preemption is deferred.
const time_slice_ticks: u64 = 10;

const ReadyQueue = struct {
    const Node = struct {
        thread: *thread.Thread,
        next: ?*Node,
    };

    head: ?*Node = null,
    tail: ?*Node = null,

    fn push(self: *ReadyQueue, t: *thread.Thread) SchedulerError!void {
        const node_mem = heap.kmalloc(@sizeOf(Node)) catch return SchedulerError.OutOfMemory;
        const node: *Node = @ptrCast(@alignCast(node_mem));
        node.* = .{
            .thread = t,
            .next = null,
        };
        t.state = .ready;

        if (self.tail) |tail| {
            tail.next = node;
            self.tail = node;
        } else {
            self.head = node;
            self.tail = node;
        }
    }

    fn pop(self: *ReadyQueue) ?*thread.Thread {
        const head = self.head orelse return null;
        const t = head.thread;
        self.head = head.next;
        if (self.head == null) self.tail = null;
        heap.kfree(@ptrCast(head)) catch {};
        return t;
    }
};

pub const SchedulerState = struct {
    bootstrap: thread.Thread = undefined,
    idle_thread: *thread.Thread = undefined,
    ready_queue: ReadyQueue = .{},
    preempt_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    ticks: u64 = 0,
};
var default_state: SchedulerState = .{};
var state: *SchedulerState = &default_state;

pub fn installState(next: *SchedulerState) void {
    state = next;
    state.* = .{};
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
    proc: ?*anyopaque,
) SchedulerError!*thread.Thread {
    const t = thread.create(entry, name, thread.default_stack_size) catch return SchedulerError.OutOfMemory;
    t.process = proc;
    try state.ready_queue.push(t);
    return t;
}

pub fn onTimerTick() void {
    state.ticks += 1;
    if (state.ticks % time_slice_ticks == 0) {
        state.preempt_requested.store(true, .monotonic);
    }
}

pub fn yieldIfRequested() void {
    if (state.preempt_requested.swap(false, .monotonic)) {
        yield();
    }
}

pub fn cooperativePoll() void {
    cpu.sti();
    if (thread.currentProcessPtr()) |raw| {
        const proc: *process.Process = @ptrCast(@alignCast(raw));
        signal.tryApply(proc);
    }
    yieldIfRequested();
    yield();
    cpu.cli();
}

pub fn yield() void {
    tty.get().pollCtrlC();
    if (tty.get().takePendingCtrlC()) |pid| {
        _ = signal.send(pid, abi_signal.SIGINT);
    }
    const self = thread.currentThread() orelse return;
    if (self.state != .dead and self != state.idle_thread) {
        state.ready_queue.push(self) catch {
            hal.console.println("ready queue push failed", .{});
            cpu.haltForever();
        };
    }
    schedule();
}

pub fn start() noreturn {
    hal.console.println("\n--- Scheduler ---", .{});

    init_shell.launch();

    hal.console.println("Enabling interrupts", .{});
    cpu.sti();
    schedule();
    cpu.haltForever();
}

fn schedule() void {
    const self = thread.currentThread() orelse return;
    const next = state.ready_queue.pop() orelse state.idle_thread;
    if (next == self) return;
    self.switchTo(next);
    if (next.process) |raw| {
        const proc: *process.Process = @ptrCast(@alignCast(raw));
        signal.tryApply(proc);
    }
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
