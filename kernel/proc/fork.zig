const process = @import("process.zig");
const scheduler = @import("scheduler.zig");
const thread = @import("thread.zig");
const user_fork = @import("user_fork.zig");
const gdt = @import("../arch/x86_64/gdt.zig");
const hal = @import("../hal.zig");
const tty = @import("../drivers/tty.zig");

var pending_child: ?*process.Process = null;
var pending_ctx: user_fork.ForkUserContext = undefined;

pub fn forkFromSyscall(ctx: user_fork.ForkUserContext) i64 {
    hal.console.println("forkFromSyscall enter", .{});
    const parent = process.currentProcess() orelse return -1;

    const child = process.forkChild(parent) catch |err| switch (err) {
        process.ProcessError.OutOfMemory => return -12,
        process.ProcessError.TooManyProcesses => return -11,
        else => return -1,
    };

    pending_child = child;
    pending_ctx = ctx;

    _ = scheduler.spawnWithProcess(forkChildEntry, "fork-child", child) catch {
        process.destroy(child);
        return -12;
    };

    tty.get().noteFork(parent.id, child.id);
    scheduler.yield();
    hal.console.println("fork parent={d} child={d}", .{ parent.id, child.id });
    return @intCast(child.id);
}

fn forkChildEntry() callconv(.{ .x86_64_sysv = .{} }) noreturn {
    const child = pending_child orelse thread.exit();
    const ctx = pending_ctx;
    pending_child = null;

    process.setCurrent(child);
    child.address_space.activate();
    child.state = .running;

    const self = thread.currentThread() orelse thread.exit();
    const kstack = (@intFromPtr(self.stack) + self.stack_size) & ~@as(u64, 15);
    gdt.setKernelStack(kstack);

    hal.console.println("fork-child pid={d} rip=0x{x} rsp=0x{x}", .{ child.id, ctx.user_rip, ctx.user_rsp });
    user_fork.returnToUser(ctx, 0);
}
