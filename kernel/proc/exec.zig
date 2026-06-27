const process = @import("process.zig");
const programs = @import("programs.zig");
const thread = @import("thread.zig");

pub const ExecError = error{
    NotFound,
    NotFile,
    OutOfMemory,
    InvalidElf,
    NoProcess,
    IoError,
    PathTooLong,
};

/// Replace the current process image with `path` (Linux `execve`). Does not return on success.
pub fn execve(path: []const u8) ExecError!noreturn {
    const proc = process.currentProcess() orelse return ExecError.NoProcess;

    const image_buf = programs.load(path) catch |err| switch (err) {
        programs.LoadError.NotFound => return ExecError.NotFound,
        programs.LoadError.NotFile => return ExecError.NotFile,
        programs.LoadError.PathTooLong => return ExecError.PathTooLong,
        programs.LoadError.OutOfMemory => return ExecError.OutOfMemory,
        programs.LoadError.TooLarge => return ExecError.InvalidElf,
        programs.LoadError.NotReady, programs.LoadError.IoError => return ExecError.IoError,
    };
    defer programs.free(image_buf);

    process.resetAddressSpace(proc) catch return ExecError.OutOfMemory;

    const loaded = process.loadElf(proc, image_buf) catch return ExecError.InvalidElf;
    proc.brk = process.user_brk_base;

    const self = thread.currentThread() orelse thread.exit();
    const kstack = (@intFromPtr(self.stack) + self.stack_size) & ~@as(u64, 15);
    process.enterUser(proc, loaded, kstack);
}
