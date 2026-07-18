//! Signal and exception metadata shared by crash reporting.
const abi_signal = @import("abi_signal");

pub fn exitStatusForVector(vector: u64) u32 {
    return 128 + signalForVector(vector).number();
}

pub fn signalForVector(vector: u64) abi_signal.Signal {
    return switch (vector) {
        0, 4, 7, 8 => .fpe,
        5 => .trap,
        6 => .ill,
        11 => .segv,
        13, 14 => .segv,
        17 => .bus,
        else => .ill,
    };
}

pub fn exceptionName(vector: u64) []const u8 {
    return switch (vector) {
        0 => "#DE divide error",
        4 => "#OF overflow",
        5 => "#BR breakpoint",
        6 => "#UD invalid opcode",
        7 => "#NM device not available",
        8 => "#DF double fault",
        11 => "#NP segment not present",
        13 => "#GP general protection fault",
        14 => "#PF page fault",
        17 => "#AC alignment check",
        else => "CPU exception",
    };
}

pub fn signalName(signal: abi_signal.Signal) []const u8 {
    return switch (signal) {
        .int => "SIGINT",
        .ill => "SIGILL",
        .trap => "SIGTRAP",
        .bus => "SIGBUS",
        .fpe => "SIGFPE",
        .segv => "SIGSEGV",
        .chld => "SIGCHLD",
        else => "SIG???",
    };
}

const PfErr = packed struct(u64) {
    present: u1,
    write: u1,
    user: u1,
    reserved: u1,
    fetch: u1,
    _: u59 = 0,
};

pub fn pageFaultDescription(code: u64) []const u8 {
    const err: PfErr = @bitCast(code);
    if (err.fetch != 0) return "instruction fetch to non-executable page";
    if (err.present == 0) {
        if (err.write != 0) return "write to unmapped page";
        return "read from unmapped page";
    }
    if (err.write != 0) return "write to read-only page";
    return "access violation";
}
