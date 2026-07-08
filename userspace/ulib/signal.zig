const abi_signal = @import("abi_signal");
const syscall = @import("syscall.zig");

pub const SIGINT = abi_signal.SIGINT;
pub const SIGCHLD = abi_signal.SIGCHLD;
pub const SIGKILL = abi_signal.SIGKILL;
pub const SIGTERM = abi_signal.SIGTERM;
pub const SIG_DFL = abi_signal.SIG_DFL;
pub const SIG_IGN = abi_signal.SIG_IGN;
pub const SIG_BLOCK = abi_signal.SIG_BLOCK;
pub const SIG_UNBLOCK = abi_signal.SIG_UNBLOCK;
pub const SIG_SETMASK = abi_signal.SIG_SETMASK;
pub const Sigaction = abi_signal.Sigaction;

pub fn sigaction(signum: u32, act: ?*const Sigaction, oldact: ?*Sigaction) isize {
    const act_ptr: u64 = if (act) |a| @intFromPtr(a) else 0;
    const old_ptr: u64 = if (oldact) |o| @intFromPtr(o) else 0;
    return syscall.rtSigaction(signum, act_ptr, old_ptr, abi_signal.sigset_wordsize);
}

pub fn sigprocmask(how: i32, set: ?*const u64, oldset: ?*u64) isize {
    const set_ptr: u64 = if (set) |s| @intFromPtr(s) else 0;
    const old_ptr: u64 = if (oldset) |o| @intFromPtr(o) else 0;
    return syscall.rtSigprocmask(@intCast(how), set_ptr, old_ptr, abi_signal.sigset_wordsize);
}

pub fn kill(pid: isize, signum: u32) isize {
    return syscall.kill(@bitCast(@as(u64, @intCast(pid))), signum);
}

pub fn ignore(signum: u32) isize {
    const act = Sigaction{ .sa_handler = SIG_IGN, .sa_flags = 0, .sa_restorer = 0, .sa_mask = 0 };
    return sigaction(signum, &act, null);
}
