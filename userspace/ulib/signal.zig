const abi_signal = @import("abi_signal");
const syscall = @import("syscall.zig");

pub const Signal = abi_signal.Signal;
pub const Disposition = abi_signal.Disposition;
pub const SigHow = abi_signal.SigHow;
pub const Sigaction = abi_signal.Sigaction;

pub fn sigaction(signum: Signal, act: ?*const Sigaction, oldact: ?*Sigaction) isize {
    const act_ptr: u64 = if (act) |a| @intFromPtr(a) else 0;
    const old_ptr: u64 = if (oldact) |o| @intFromPtr(o) else 0;
    return syscall.rtSigaction(signum.number(), act_ptr, old_ptr, abi_signal.sigset_wordsize);
}

pub fn sigprocmask(how: SigHow, set: ?*const u64, oldset: ?*u64) isize {
    const set_ptr: u64 = if (set) |s| @intFromPtr(s) else 0;
    const old_ptr: u64 = if (oldset) |o| @intFromPtr(o) else 0;
    return syscall.rtSigprocmask(@intCast(@intFromEnum(how)), set_ptr, old_ptr, abi_signal.sigset_wordsize);
}

pub fn kill(pid: isize, signum: Signal) isize {
    return syscall.kill(@bitCast(@as(i64, pid)), signum.number());
}

pub fn ignore(signum: Signal) isize {
    const act = Sigaction{
        .sa_handler = @intFromEnum(Disposition.ignore),
        .sa_flags = 0,
        .sa_restorer = 0,
        .sa_mask = 0,
    };
    return sigaction(signum, &act, null);
}

pub fn default(signum: Signal) isize {
    const act = Sigaction{
        .sa_handler = @intFromEnum(Disposition.default),
        .sa_flags = 0,
        .sa_restorer = 0,
        .sa_mask = 0,
    };
    return sigaction(signum, &act, null);
}
