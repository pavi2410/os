const process = @import("process.zig");
const scheduler = @import("scheduler.zig");
const thread = @import("thread.zig");
const user_fork = @import("user_fork.zig");

var pending_child: ?*process.Process = null;
var pending_ctx: user_fork.ForkUserContext = undefined;

pub fn forkFromSyscall(ctx: user_fork.ForkUserContext) i64 {
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

    return @intCast(child.id);
}

fn forkChildEntry() callconv(.{ .x86_64_sysv = .{} }) noreturn {
    const child = pending_child orelse thread.exit();
    const ctx = pending_ctx;
    pending_child = null;

    process.setCurrent(child);
    child.address_space.activate();
    child.state = .running;

    user_fork.returnToUser(ctx, 0);
}
