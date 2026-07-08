/// Linux-compatible signal numbers and helpers shared by kernel and userspace.
pub const NSIG: u32 = 64;

pub const SIGHUP: u32 = 1;
pub const SIGINT: u32 = 2;
pub const SIGQUIT: u32 = 3;
pub const SIGILL: u32 = 4;
pub const SIGTRAP: u32 = 5;
pub const SIGABRT: u32 = 6;
pub const SIGBUS: u32 = 7;
pub const SIGFPE: u32 = 8;
pub const SIGKILL: u32 = 9;
pub const SIGUSR1: u32 = 10;
pub const SIGSEGV: u32 = 11;
pub const SIGUSR2: u32 = 12;
pub const SIGPIPE: u32 = 13;
pub const SIGALRM: u32 = 14;
pub const SIGTERM: u32 = 15;
pub const SIGCHLD: u32 = 17;
pub const SIGSTOP: u32 = 19;

pub const SIG_DFL: u64 = 0;
pub const SIG_IGN: u64 = 1;

pub const SIG_BLOCK: i32 = 0;
pub const SIG_UNBLOCK: i32 = 1;
pub const SIG_SETMASK: i32 = 2;

pub const sigset_wordsize: usize = 8;

/// Minimal Linux `struct sigaction` (handler + flags + restorer + mask).
pub const Sigaction = extern struct {
    sa_handler: u64,
    sa_flags: u64,
    sa_restorer: u64,
    sa_mask: u64,
};

pub fn isValid(signum: u32) bool {
    return signum > 0 and signum < NSIG;
}

pub fn mask(signum: u32) u64 {
    return @as(u64, 1) << @intCast(signum - 1);
}

pub fn blockMask(current: u64, set: u64) u64 {
    return current | set;
}

pub fn unblockMask(current: u64, set: u64) u64 {
    return current & ~set;
}

pub fn setMask(set: u64) u64 {
    return set;
}

pub fn waitStatusForExit(code: u32) u32 {
    return (code & 0xff) << 8;
}

pub fn waitStatusForSignal(sig: u32) u32 {
    return sig & 0x7f;
}
