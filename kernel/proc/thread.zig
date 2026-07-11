const cpu = @import("../arch/x86_64/cpu.zig");
const gdt = @import("../arch/x86_64/gdt.zig");
const heap = @import("../mm/heap.zig");
const hal = @import("../hal.zig");
const user_mode = @import("../arch/x86_64/user.zig");
const arch_context = @import("../arch/x86_64/context.zig");

const ActivateCr3Fn = *const fn (?*anyopaque) void;

var activate_cr3: ActivateCr3Fn = &noopActivateCr3;

fn noopActivateCr3(_: ?*anyopaque) void {}

pub fn setActivateCr3Hook(hook: ActivateCr3Fn) void {
    activate_cr3 = hook;
}

pub const ThreadError = error{
    OutOfMemory,
};

pub const State = enum {
    ready,
    running,
    blocked,
    dead,
};

/// Callee-saved registers plus stack pointer and resume address for switch_context.
pub const SavedContext = extern struct {
    rbx: u64,
    rbp: u64,
    r12: u64,
    r13: u64,
    r14: u64,
    r15: u64,
    rsp: u64,
    rip: u64,
};

pub const EntryFn = *const fn () callconv(.{ .x86_64_sysv = .{} }) noreturn;

pub const Thread = struct {
    id: usize,
    name: []const u8,
    stack: [*]u8,
    stack_size: usize,
    context: SavedContext,
    state: State,
    /// User process bound to this kernel thread (null for idle/bootstrap).
    process: ?*anyopaque = null,
    /// Captured syscall state used only by a newly forked child.
    fork_context: ?user_mode.ForkContext = null,

    pub fn switchTo(self: *Thread, other: *Thread) void {
        const prev_state = self.state;
        if (self.state != .dead) {
            self.state = .ready;
        }
        other.state = .running;
        current = other;
        other.activateKernelStack();
        activate_cr3(other.process);
        arch_context.switchContext(@ptrCast(&self.context), @ptrCast(&other.context));
        if (self.state != .dead) {
            activate_cr3(self.process);
        } else {
            activate_cr3(null);
        }
        current = self;
        self.state = prev_state;
        self.activateKernelStack();
    }

    /// Point the TSS `rsp0` at this thread's kernel stack so ring-3 syscalls and
    /// interrupts land on the correct per-thread stack.
    fn activateKernelStack(self: *Thread) void {
        if (self.stack_size == 0) return;
        const top = (@intFromPtr(self.stack) + self.stack_size) & ~@as(u64, 15);
        gdt.setKernelStack(top);
    }
};

pub const default_stack_size: usize = 32 * 1024;
const max_thread_stacks = 32;

// Ring-3 entries use TSS.rsp0 before any Zig code can run. Keep these stacks
// in the statically mapped kernel image rather than the dynamically mapped
// heap, so every process CR3 can always service an interrupt or syscall.
var thread_stacks: [max_thread_stacks][default_stack_size]u8 align(16) = undefined;
var next_stack: usize = 0;

var next_id: usize = 1;
var current: ?*Thread = null;
var on_exit: ?*const fn () noreturn = null;

comptime {
    if (@offsetOf(SavedContext, "rbx") != 0) @compileError("SavedContext layout mismatch");
    if (@offsetOf(SavedContext, "rbp") != 8) @compileError("SavedContext layout mismatch");
    if (@offsetOf(SavedContext, "r12") != 16) @compileError("SavedContext layout mismatch");
    if (@offsetOf(SavedContext, "r13") != 24) @compileError("SavedContext layout mismatch");
    if (@offsetOf(SavedContext, "r14") != 32) @compileError("SavedContext layout mismatch");
    if (@offsetOf(SavedContext, "r15") != 40) @compileError("SavedContext layout mismatch");
    if (@offsetOf(SavedContext, "rsp") != 48) @compileError("SavedContext layout mismatch");
    if (@offsetOf(SavedContext, "rip") != 56) @compileError("SavedContext layout mismatch");
    if (@sizeOf(SavedContext) != 64) @compileError("SavedContext must be 64 bytes");
}

pub fn currentThread() ?*Thread {
    return current;
}

pub fn setCurrent(t: ?*Thread) void {
    current = t;
}

pub fn setProcess(proc: ?*anyopaque) void {
    const t = current orelse return;
    t.process = proc;
}

pub fn currentProcessPtr() ?*anyopaque {
    const t = current orelse return null;
    return t.process;
}

pub fn setExitHandler(handler: *const fn () noreturn) void {
    on_exit = handler;
}

pub fn create(entry: EntryFn, name: []const u8, stack_size: usize) ThreadError!*Thread {
    if (stack_size > default_stack_size or next_stack >= thread_stacks.len) {
        return ThreadError.OutOfMemory;
    }
    const thread_mem = heap.kmalloc(@sizeOf(Thread)) catch return ThreadError.OutOfMemory;
    const stack_mem: [*]u8 = &thread_stacks[next_stack];
    next_stack += 1;

    const thread: *Thread = @ptrCast(@alignCast(thread_mem));
    thread.* = .{
        .id = next_id,
        .name = name,
        .stack = stack_mem,
        .stack_size = stack_size,
        .context = initContext(stack_mem, stack_size, entry),
        .state = .ready,
    };
    next_id += 1;
    return thread;
}

pub fn exit() noreturn {
    if (current) |thread| {
        thread.state = .dead;
    }
    if (on_exit) |handler| {
        handler();
    }
    hal.console.println("\nthread exited without a scheduler", .{});
    cpu.haltForever();
}

fn initContext(stack: [*]u8, stack_size: usize, entry: EntryFn) SavedContext {
    var sp: usize = (@intFromPtr(stack) + stack_size) & ~@as(usize, 15);
    sp -= 8;
    @as(*u64, @ptrFromInt(sp)).* = @intFromPtr(entry);
    return .{
        .rbx = 0,
        .rbp = 0,
        .r12 = 0,
        .r13 = 0,
        .r14 = 0,
        .r15 = 0,
        .rsp = sp,
        .rip = @intFromPtr(entry),
    };
}

/// Cooperative ping-pong between bootstrap and a worker thread.
pub fn runSwitchTest(switch_target: usize) void {
    hal.console.println("\n--- Thread context switch test ---", .{});

    var bootstrap = Thread{
        .id = 0,
        .name = "bootstrap",
        .stack = undefined,
        .stack_size = 0,
        .context = undefined,
        .state = .running,
    };
    current = &bootstrap;
    switch_test_bootstrap = &bootstrap;
    switch_test_target = switch_target;
    switch_test_counter = 0;

    const worker = create(switchTestWorker, "switch-worker", default_stack_size) catch {
        hal.console.println("thread create failed", .{});
        cpu.haltForever();
    };

    var bootstrap_switches: usize = 0;
    while (switch_test_counter < switch_target) {
        bootstrap_switches += 1;
        bootstrap.switchTo(worker);
    }

    hal.console.println("context switches: worker={d} bootstrap={d}", .{
        switch_test_counter,
        bootstrap_switches,
    });
    current = &bootstrap;
    switch_test_bootstrap = null;
}

var switch_test_bootstrap: ?*Thread = null;
var switch_test_counter: usize = 0;
var switch_test_target: usize = 0;

fn switchTestWorker() callconv(.{ .x86_64_sysv = .{} }) noreturn {
    const bootstrap = switch_test_bootstrap orelse exit();
    while (switch_test_counter < switch_test_target) {
        switch_test_counter += 1;
        const worker = currentThread() orelse exit();
        worker.switchTo(bootstrap);
    }
    exit();
}
