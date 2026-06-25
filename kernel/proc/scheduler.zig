const cpu = @import("../arch/x86_64/cpu.zig");
const heap = @import("../mm/heap.zig");
const serial = @import("../arch/x86_64/serial.zig");
const syscall_test = @import("../syscall/test.zig");
const thread = @import("thread.zig");
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

var bootstrap: thread.Thread = undefined;
var idle_thread: *thread.Thread = undefined;
var ready_queue: ReadyQueue = .{};
var preempt_requested = std.atomic.Value(bool).init(false);
var scheduler_ticks: u64 = 0;

pub fn init() void {
    bootstrap = .{
        .id = 0,
        .name = "bootstrap",
        .stack = undefined,
        .stack_size = 0,
        .context = undefined,
        .state = .running,
    };
    thread.setCurrent(&bootstrap);

    idle_thread = thread.create(idleEntry, "idle", thread.default_stack_size) catch {
        serial.writeString("idle thread create failed\r\n");
        cpu.haltForever();
    };

    thread.setExitHandler(exitCurrent);
}

pub fn spawn(entry: thread.EntryFn, name: []const u8) SchedulerError!void {
    const t = thread.create(entry, name, thread.default_stack_size) catch return SchedulerError.OutOfMemory;
    try ready_queue.push(t);
}

pub fn onTimerTick() void {
    scheduler_ticks += 1;
    if (scheduler_ticks % time_slice_ticks == 0) {
        preempt_requested.store(true, .monotonic);
    }
}

pub fn yieldIfRequested() void {
    if (preempt_requested.swap(false, .monotonic)) {
        yield();
    }
}

pub fn yield() void {
    const self = thread.currentThread() orelse return;
    if (self.state != .dead and self != idle_thread) {
        ready_queue.push(self) catch {
            serial.writeString("ready queue push failed\r\n");
            cpu.haltForever();
        };
    }
    schedule();
}

pub fn start() noreturn {
    serial.writeString("\r\n--- Scheduler ---\r\n");

    spawn(syscall_test.threadEntry, "syscall-test") catch {
        serial.writeString("spawn syscall-test failed\r\n");
        cpu.haltForever();
    };

    spawn(demoThreadA, "thread-a") catch {
        serial.writeString("spawn thread-a failed\r\n");
        cpu.haltForever();
    };
    spawn(demoThreadB, "thread-b") catch {
        serial.writeString("spawn thread-b failed\r\n");
        cpu.haltForever();
    };

    serial.writeString("Spawned demo threads, enabling interrupts\r\n");
    cpu.sti();
    schedule();
    cpu.haltForever();
}

fn schedule() void {
    const self = thread.currentThread() orelse return;
    const next = ready_queue.pop() orelse idle_thread;
    if (next == self) return;
    self.switchTo(next);
}

fn exitCurrent() noreturn {
    yield();
    cpu.haltForever();
}

fn idleEntry() callconv(.{ .x86_64_sysv = .{} }) noreturn {
    while (true) {
        yieldIfRequested();
        cpu.hlt();
    }
}

fn demoThreadA() callconv(.{ .x86_64_sysv = .{} }) noreturn {
    while (true) {
        serial.writeString("A");
        yieldIfRequested();
    }
}

fn demoThreadB() callconv(.{ .x86_64_sysv = .{} }) noreturn {
    while (true) {
        serial.writeString("B");
        yieldIfRequested();
    }
}
