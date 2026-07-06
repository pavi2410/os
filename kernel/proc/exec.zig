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
pub fn execve(path: []const u8, argv: []const []const u8) ExecError!noreturn {
    const proc = process.currentProcess() orelse return ExecError.NoProcess;

    var path_buf: [256]u8 = undefined;
    if (path.len >= path_buf.len) return ExecError.PathTooLong;
    @memcpy(path_buf[0..path.len], path);
    const path_copy = path_buf[0..path.len];

    var arg_bufs: [16][256]u8 = undefined;
    var argv_copy: [16][]const u8 = undefined;
    if (argv.len > argv_copy.len) return ExecError.PathTooLong;
    for (argv, 0..) |arg, i| {
        if (arg.len >= arg_bufs[0].len) return ExecError.PathTooLong;
        @memcpy(arg_bufs[i][0..arg.len], arg);
        argv_copy[i] = arg_bufs[i][0..arg.len];
    }
    const argv_slice = argv_copy[0..argv.len];

    const image_buf = programs.load(path_copy) catch |err| switch (err) {
        programs.LoadError.NotFound => return ExecError.NotFound,
        programs.LoadError.NotFile => return ExecError.NotFile,
        programs.LoadError.PathTooLong => return ExecError.PathTooLong,
        programs.LoadError.OutOfMemory => return ExecError.OutOfMemory,
        programs.LoadError.TooLarge => return ExecError.InvalidElf,
        programs.LoadError.NotReady, programs.LoadError.IoError => return ExecError.IoError,
    };
    defer programs.free(image_buf);

    process.resetAddressSpace(proc) catch return ExecError.OutOfMemory;

    const loaded = process.loadElf(proc, image_buf, argv_slice) catch return ExecError.InvalidElf;
    proc.brk = process.user_brk_base;

    const self = thread.currentThread() orelse thread.exit();
    const kstack = (@intFromPtr(self.stack) + self.stack_size) & ~@as(u64, 15);
    process.enterUser(proc, loaded, kstack);
}
