const abi_signal = @import("abi_signal");
const process = @import("process.zig");

pub const Action = enum {
    dfl,
    ign,
};

pub const SignalState = struct {
    pending: u64 = 0,
    blocked: u64 = 0,
    actions: [abi_signal.NSIG]Action = defaultActions(),

    pub fn init() SignalState {
        return .{};
    }
};

pub fn defaultActions() [abi_signal.NSIG]Action {
    var actions: [abi_signal.NSIG]Action = undefined;
    for (&actions) |*slot| slot.* = .dfl;
    return actions;
}

pub fn inheritFromParent(child: *process.Process, parent: *const process.Process) void {
    child.signals.blocked = parent.signals.blocked;
    child.signals.actions = parent.signals.actions;
    child.signals.pending = 0;
}

pub fn resetOnExec(proc: *process.Process) void {
    var i: u32 = 0;
    while (i < abi_signal.NSIG) : (i += 1) {
        proc.signals.actions[i] = if (proc.signals.actions[i] == .ign) .ign else .dfl;
    }
    proc.signals.pending = 0;
    proc.signals.blocked = 0;
}

pub fn send(pid: usize, sig: u32) bool {
    if (!abi_signal.isValid(sig)) return false;
    const proc = process.lookup(pid) orelse return false;
    queue(proc, sig);
    return true;
}

pub fn queue(proc: *process.Process, sig: u32) void {
    const bit = abi_signal.mask(sig);
    proc.signals.pending |= bit;

    if (sig == abi_signal.SIGKILL) {
        tryApply(proc);
        return;
    }
    if (proc.signals.blocked & bit != 0) return;
    tryApply(proc);
}

pub fn tryApplyCurrent() void {
    const proc = process.currentProcess() orelse return;
    tryApply(proc);
}

pub fn tryApply(proc: *process.Process) void {
    if (process.currentProcess() != proc) return;
    applyPending(proc);
}

pub fn applyPending(proc: *process.Process) void {
    var sig: u32 = 1;
    while (sig < abi_signal.NSIG) : (sig += 1) {
        const bit = abi_signal.mask(sig);
        if (proc.signals.pending & bit == 0) continue;
        if (sig != abi_signal.SIGKILL and proc.signals.blocked & bit != 0) continue;

        proc.signals.pending &= ~bit;

        switch (resolveAction(proc, sig)) {
            .ignore => {},
            .default_ignore => {},
            .terminate => terminateBySignal(proc, sig),
        }
    }
}

fn resolveAction(proc: *const process.Process, sig: u32) enum {
    ignore,
    default_ignore,
    terminate,
} {
    if (sig == abi_signal.SIGCHLD) {
        return switch (proc.signals.actions[sig]) {
            .ign => .ignore,
            .dfl => .default_ignore,
        };
    }
    return switch (proc.signals.actions[sig]) {
        .ign => .ignore,
        .dfl => .terminate,
    };
}

pub fn terminateBySignal(proc: *process.Process, sig: u32) noreturn {
    const was_current = process.currentProcess() == proc;
    if (!was_current) {
        process.setCurrent(proc);
    }
    process.terminateCurrent(abi_signal.waitStatusForSignal(sig));
}

pub fn sigaction(proc: *process.Process, signum: u32, act: ?abi_signal.Sigaction) ActionError!Action {
    if (!abi_signal.isValid(signum)) return error.Invalid;
    if (signum == abi_signal.SIGKILL or signum == abi_signal.SIGSTOP) return error.Invalid;

    const old = proc.signals.actions[signum];
    if (act) |new_act| {
        const handler = new_act.sa_handler;
        proc.signals.actions[signum] = switch (handler) {
            abi_signal.SIG_DFL => .dfl,
            abi_signal.SIG_IGN => .ign,
            else => return error.Invalid,
        };
    }
    return old;
}

pub fn sigprocmask(proc: *process.Process, how: i32, set: u64) i64 {
    const old = proc.signals.blocked;
    proc.signals.blocked = switch (how) {
        abi_signal.SIG_BLOCK => abi_signal.blockMask(old, set),
        abi_signal.SIG_UNBLOCK => abi_signal.unblockMask(old, set),
        abi_signal.SIG_SETMASK => abi_signal.setMask(set),
        else => return -22,
    };
    proc.signals.blocked &= ~abi_signal.mask(abi_signal.SIGKILL);
    tryApply(proc);
    return @bitCast(@as(i64, @intCast(old)));
}

pub fn actionToHandler(action: Action) u64 {
    return switch (action) {
        .dfl => abi_signal.SIG_DFL,
        .ign => abi_signal.SIG_IGN,
    };
}

pub const ActionError = error{
    Invalid,
};

pub fn notifyChildExit(parent_id: usize) void {
    if (parent_id == process.no_parent) return;
    if (process.lookup(parent_id)) |parent| {
        queue(parent, abi_signal.SIGCHLD);
    }
}

pub fn onProcessExit(pid: usize) void {
    const tty = @import("../drivers/tty.zig");
    tty.get().clearForegroundIf(pid);
}
