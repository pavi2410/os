const numbers = @import("numbers.zig");
const serial = @import("../arch/x86_64/serial.zig");
const thread = @import("../proc/thread.zig");

const msg = "syscall test ok\r\n";

pub fn runInThread() void {
    serial.writeString("\r\n--- Syscall test ---\r\n");

    const written = invokeSyscall(.{
        .nr = numbers.write,
        .arg0 = 1,
        .arg1 = @intFromPtr(msg.ptr),
        .arg2 = msg.len,
    });

    if (written != @as(i64, @intCast(msg.len))) {
        serial.printf("syscall write failed: {d}\r\n", .{written});
        return;
    }

    serial.writeString("syscall write ok\r\n");
}

/// Issue a syscall from ring 0; the entry stub returns via `jmp` for kernel callers.
fn invokeSyscall(args: struct {
    nr: u64,
    arg0: u64 = 0,
    arg1: u64 = 0,
    arg2: u64 = 0,
    arg3: u64 = 0,
    arg4: u64 = 0,
    arg5: u64 = 0,
}) i64 {
    return asm volatile (
        \\syscall
        : [ret] "={rax}" (-> i64),
        : [nr] "{rax}" (args.nr),
          [arg0] "{rdi}" (args.arg0),
          [arg1] "{rsi}" (args.arg1),
          [arg2] "{rdx}" (args.arg2),
          [arg3] "{r10}" (args.arg3),
          [arg4] "{r8}" (args.arg4),
          [arg5] "{r9}" (args.arg5),
    );
}

/// Kernel thread entry: exercise `write`, then terminate through `exit`.
pub fn threadEntry() callconv(.{ .x86_64_sysv = .{} }) noreturn {
    runInThread();
    _ = invokeSyscall(.{ .nr = numbers.exit });
    serial.writeString("syscall exit returned unexpectedly\r\n");
    thread.exit();
}
