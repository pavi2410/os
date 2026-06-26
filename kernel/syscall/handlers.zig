const numbers = @import("numbers.zig");
const process = @import("../proc/process.zig");
const serial = @import("../arch/x86_64/serial.zig");
const thread = @import("../proc/thread.zig");
const tty = @import("../drivers/tty.zig");

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
        numbers.read => sysRead(frame.arg0, frame.arg1, frame.arg2),
        numbers.write => sysWrite(frame.arg0, frame.arg1, frame.arg2),
        numbers.brk => sysBrk(frame.arg0),
        numbers.getpid => sysGetpid(),
        numbers.exit, numbers.exit_group => sysExit(frame.arg0),
        else => ENOSYS,
    };
}

fn sysRead(fd: u64, buf_ptr: u64, count: u64) i64 {
    if (fd != 0) return EBADF;
    if (count == 0) return 0;

    const max_len: usize = 4096;
    const len: usize = @intCast(@min(count, max_len));
    const buf: [*]u8 = @ptrFromInt(buf_ptr);

    const read_len = tty.get().read(buf[0..len]) catch |err| switch (err) {
        tty.TtyError.WouldBlock => return -4, // EINTR
    };
    return @intCast(read_len);
}

fn sysWrite(fd: u64, buf_ptr: u64, count: u64) i64 {
    if (fd != 1 and fd != 2) return EBADF;
    if (count == 0) return 0;

    const max_len: usize = 4096;
    const len: usize = @intCast(@min(count, max_len));
    const buf: [*]const u8 = @ptrFromInt(buf_ptr);
    const written = tty.get().write(buf[0..len]);
    return @intCast(written);
}

fn sysBrk(addr: u64) i64 {
    const proc = process.currentProcess() orelse return -1;
    return process.sysBrk(proc, addr);
}

fn sysGetpid() i64 {
    const proc = process.currentProcess() orelse return 1;
    return @intCast(proc.id);
}

fn sysExit(status: u64) i64 {
    if (process.currentProcess() != null) {
        process.terminateCurrent(@truncate(status));
    }
    serial.printf("\r\nsyscall exit({d})\r\n", .{status});
    thread.exit();
}
