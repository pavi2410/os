const paging = @import("../arch/x86_64/paging.zig");
const process = @import("process.zig");
const scheduler = @import("scheduler.zig");
const thread = @import("thread.zig");
const user_fork = @import("user_fork.zig");

var pending_child: ?*process.Process = null;
var pending_ctx: user_fork.ForkUserContext = undefined;

pub fn forkFromSyscall(
    arg0: u64,
    arg1: u64,
    arg2: u64,
    arg3: u64,
    arg4: u64,
    arg5: u64,
    user_rip: u64,
    user_rflags: u64,
    user_rsp: u64,
) i64 {
    const parent = process.currentProcess() orelse return -1;

    const child = process.forkChild(parent) catch |err| switch (err) {
        process.ProcessError.OutOfMemory => return -12,
        process.ProcessError.TooManyProcesses => return -11,
        else => return -1,
    };

    pending_child = child;
    pending_ctx = user_fork.ForkUserContext.captureFromSyscall(
        arg0,
        arg1,
        arg2,
        arg3,
        arg4,
        arg5,
        user_rip,
        user_rflags,
        user_rsp,
    );

    scheduler.spawn(forkChildEntry, "fork-child") catch {
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
