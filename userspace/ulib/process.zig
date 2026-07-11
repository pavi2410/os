const syscall = @import("syscall.zig");

/// Process identifiers and syscall results are signed: negative values are errno.
pub const ProcessId = i64;
pub const Result = i64;

pub fn exit(status: u32) noreturn {
    syscall.exit(status);
}

pub fn getpid() ProcessId {
    return @intCast(syscall.getpid());
}

pub fn fork() Result {
    return @intCast(syscall.fork());
}

pub fn exec(path: [*:0]const u8, argv: [*:null]?[*:0]const u8, envp: [*:null]?[*:0]const u8) Result {
    return @intCast(syscall.execve(path, argv, envp));
}

pub fn wait(pid: ProcessId, status: ?*u32, options: u32) Result {
    return @intCast(syscall.waitpid(@intCast(pid), status, options));
}
