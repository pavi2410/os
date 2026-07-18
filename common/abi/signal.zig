/// Linux-compatible signal numbers and helpers shared by kernel and userspace.
pub const NSIG: u32 = 64;

pub const Signal = enum(u32) {
    hup = 1,
    int = 2,
    quit = 3,
    ill = 4,
    trap = 5,
    abrt = 6,
    bus = 7,
    fpe = 8,
    kill = 9,
    usr1 = 10,
    segv = 11,
    usr2 = 12,
    pipe = 13,
    alrm = 14,
    term = 15,
    chld = 17,
    stop = 19,

    pub fn fromInt(n: u32) ?Signal {
        return switch (n) {
            @intFromEnum(Signal.hup) => .hup,
            @intFromEnum(Signal.int) => .int,
            @intFromEnum(Signal.quit) => .quit,
            @intFromEnum(Signal.ill) => .ill,
            @intFromEnum(Signal.trap) => .trap,
            @intFromEnum(Signal.abrt) => .abrt,
            @intFromEnum(Signal.bus) => .bus,
            @intFromEnum(Signal.fpe) => .fpe,
            @intFromEnum(Signal.kill) => .kill,
            @intFromEnum(Signal.usr1) => .usr1,
            @intFromEnum(Signal.segv) => .segv,
            @intFromEnum(Signal.usr2) => .usr2,
            @intFromEnum(Signal.pipe) => .pipe,
            @intFromEnum(Signal.alrm) => .alrm,
            @intFromEnum(Signal.term) => .term,
            @intFromEnum(Signal.chld) => .chld,
            @intFromEnum(Signal.stop) => .stop,
            else => null,
        };
    }

    pub fn number(self: Signal) u32 {
        return @intFromEnum(self);
    }
};

/// Handler disposition values stored in `Sigaction.sa_handler`.
pub const Disposition = enum(u64) {
    default = 0,
    ignore = 1,
};

pub const SigHow = enum(i32) {
    block = 0,
    unblock = 1,
    setmask = 2,

    pub fn fromInt(n: i32) ?SigHow {
        return switch (n) {
            @intFromEnum(SigHow.block) => .block,
            @intFromEnum(SigHow.unblock) => .unblock,
            @intFromEnum(SigHow.setmask) => .setmask,
            else => null,
        };
    }
};

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

pub fn maskOf(sig: Signal) u64 {
    return mask(sig.number());
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

pub fn waitStatusForSignal(sig: Signal) u32 {
    return sig.number() & 0x7f;
}

comptime {
    if (@intFromEnum(Signal.int) != 2) @compileError("Signal.int must be 2");
    if (@intFromEnum(Signal.kill) != 9) @compileError("Signal.kill must be 9");
    if (@intFromEnum(Disposition.default) != 0) @compileError("Disposition.default must be 0");
    if (@intFromEnum(SigHow.block) != 0) @compileError("SigHow.block must be 0");
}
