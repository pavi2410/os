const numbers = @import("numbers.zig");
const serial = @import("../arch/x86_64/serial.zig");
const thread = @import("../proc/thread.zig");

/// Matches the stack layout built by `syscall_entry` (r9 pushed first).
pub const Frame = extern struct {
    arg5: u64,
    arg4: u64,
    arg3: u64,
    arg2: u64,
    arg1: u64,
    arg0: u64,
    nr: u64,
    user_rip: u64,
    user_rflags: u64,
};

const ENOSYS: i64 = -38;
const EBADF: i64 = -9;

pub export fn syscall_dispatch(frame: *Frame) callconv(.{ .x86_64_sysv = .{} }) i64 {
    return switch (frame.nr) {
        numbers.write => sysWrite(frame.arg0, frame.arg1, frame.arg2),
        numbers.exit => sysExit(frame.arg0),
        else => ENOSYS,
    };
}

fn sysWrite(fd: u64, buf_ptr: u64, count: u64) i64 {
    if (fd != 1 and fd != 2) return EBADF;
    if (count == 0) return 0;

    const max_len: usize = 4096;
    const len: usize = @intCast(@min(count, max_len));
    const buf: [*]const u8 = @ptrFromInt(buf_ptr);
    serial.writeString(buf[0..len]);
    return @intCast(len);
}

fn sysExit(status: u64) i64 {
    serial.printf("\r\nsyscall exit({d})\r\n", .{status});
    thread.exit();
}
