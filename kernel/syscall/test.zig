const numbers = @import("numbers.zig");
const hal = @import("../hal.zig");
const thread = @import("../proc/thread.zig");
const arch_test = @import("../arch/x86_64/syscall_test.zig");

const msg = "syscall test ok\n";

pub fn runInThread() void {
    hal.console.println("\n--- Syscall test ---", .{});

    const written = arch_test.invoke(.{
        .nr = numbers.write,
        .arg0 = 1,
        .arg1 = @intFromPtr(msg.ptr),
        .arg2 = msg.len,
    });

    if (written != @as(i64, @intCast(msg.len))) {
        hal.console.println("syscall write failed: {d}", .{written});
        return;
    }

    hal.console.println("syscall write ok", .{});
}

/// Kernel thread entry: exercise `write`, then terminate through `exit`.
pub fn threadEntry() callconv(.{ .x86_64_sysv = .{} }) noreturn {
    runInThread();
    _ = arch_test.invoke(.{ .nr = numbers.exit });
    hal.console.println("syscall exit returned unexpectedly", .{});
    thread.exit();
}
