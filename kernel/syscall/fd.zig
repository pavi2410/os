const process = @import("../proc/process.zig");

pub const Error = error{
    BadFd,
    NoProcess,
    TooManyOpenFiles,
};

pub fn currentProcess() Error!*process.Process {
    return process.currentProcess() orelse Error.NoProcess;
}

pub fn slot(proc: *process.Process, fd: u64) Error!*process.Fd {
    if (fd >= process.max_fds) return Error.BadFd;
    const entry = &proc.fds.fds[@intCast(fd)];
    if (entry.kind == .none) return Error.BadFd;
    return entry;
}

pub fn currentSlot(fd: u64) Error!*process.Fd {
    return slot(try currentProcess(), fd);
}

pub fn expectFile(fd: u64) Error!*process.Fd {
    const entry = try currentSlot(fd);
    if (entry.kind != .file) return Error.BadFd;
    return entry;
}

pub fn expectSocket(fd: u64) Error!*process.Fd {
    const entry = try currentSlot(fd);
    if (entry.kind != .socket) return Error.BadFd;
    return entry;
}

pub fn alloc(proc: *process.Process) Error!usize {
    return proc.fds.allocFd() orelse Error.TooManyOpenFiles;
}
