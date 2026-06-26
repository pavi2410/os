const cpu = @import("../arch/x86_64/cpu.zig");
const gdt = @import("../arch/x86_64/gdt.zig");
const heap = @import("../mm/heap.zig");
const serial = @import("../arch/x86_64/serial.zig");

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

    pub fn switchTo(self: *Thread, other: *Thread) void {
        const prev_state = self.state;
        self.state = .ready;
        other.state = .running;
        current = other;
        other.activateKernelStack();
        switch_context(&self.context, &other.context);
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

var next_id: usize = 1;
var current: ?*Thread = null;
var on_exit: ?*const fn () noreturn = null;

extern fn switch_context(from: *SavedContext, to: *SavedContext) callconv(.{ .x86_64_sysv = .{} }) void;

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

comptime {
    asm (
        \\.global switch_context
        \\.type switch_context, @function
        \\switch_context:
        \\  mov %rbx, 0(%rdi)
        \\  mov %rbp, 8(%rdi)
        \\  mov %r12, 16(%rdi)
        \\  mov %r13, 24(%rdi)
        \\  mov %r14, 32(%rdi)
        \\  mov %r15, 40(%rdi)
        \\  mov %rsp, 48(%rdi)
        \\  mov (%rsp), %rax
        \\  mov %rax, 56(%rdi)
        \\
        \\  mov 0(%rsi), %rbx
        \\  mov 8(%rsi), %rbp
        \\  mov 16(%rsi), %r12
        \\  mov 24(%rsi), %r13
        \\  mov 32(%rsi), %r14
        \\  mov 40(%rsi), %r15
        \\  mov 48(%rsi), %rsp
        \\  ret
    );
}

pub fn currentThread() ?*Thread {
    return current;
}

pub fn setCurrent(t: ?*Thread) void {
    current = t;
}

pub fn setExitHandler(handler: *const fn () noreturn) void {
    on_exit = handler;
}

pub fn create(entry: EntryFn, name: []const u8, stack_size: usize) ThreadError!*Thread {
    const thread_mem = heap.kmalloc(@sizeOf(Thread)) catch return ThreadError.OutOfMemory;
    const stack_mem = heap.kmalloc(stack_size) catch {
        heap.kfree(thread_mem) catch {};
        return ThreadError.OutOfMemory;
    };

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
    serial.writeString("\r\nthread exited without a scheduler\r\n");
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
    serial.writeString("\r\n--- Thread context switch test ---\r\n");

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
        serial.writeString("thread create failed\r\n");
        cpu.haltForever();
    };

    var bootstrap_switches: usize = 0;
    while (switch_test_counter < switch_target) {
        bootstrap_switches += 1;
        bootstrap.switchTo(worker);
    }

    serial.printf("context switches: worker={d} bootstrap={d}\r\n", .{
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
