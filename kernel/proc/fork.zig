const process = @import("process.zig");
const scheduler = @import("scheduler.zig");
const thread = @import("thread.zig");
const user_mode = @import("../arch/x86_64/user.zig");
const gdt = @import("../arch/x86_64/gdt.zig");
const tty = @import("../drivers/tty.zig");

pub fn forkFromSyscall(ctx: user_mode.ForkContext) i64 {
    const parent = process.currentProcess() orelse return -1;

    const child = process.forkChild(parent) catch |err| switch (err) {
        process.ProcessError.OutOfMemory => return -12,
        process.ProcessError.TooManyProcesses => return -11,
        else => return -1,
    };

    const child_thread = scheduler.spawnWithProcess(forkChildEntry, "fork-child", child) catch {
        process.destroy(child);
        return -12;
    };
    child_thread.fork_context = ctx;

    tty.get().noteFork(parent.id, child.id);
    return @intCast(child.id);
}

fn forkChildEntry() callconv(.{ .x86_64_sysv = .{} }) noreturn {
    const self = thread.currentThread() orelse thread.exit();
    const child: *process.Process = @ptrCast(@alignCast(self.process orelse thread.exit()));
    const ctx = self.fork_context orelse thread.exit();
    self.fork_context = null;

    process.setCurrent(child);
    child.address_space.activate();
    child.state = .running;

    const kstack = (@intFromPtr(self.stack) + self.stack_size) & ~@as(u64, 15);
    gdt.setKernelStack(kstack);

    user_mode.returnAfterFork(ctx, 0);
}
