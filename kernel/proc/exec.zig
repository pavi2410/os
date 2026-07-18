const process = @import("process.zig");
const programs = @import("programs.zig");
const signal_mod = @import("signal.zig");
const thread = @import("thread.zig");
const user_loader = @import("../mm/user_loader.zig");
const mmap_mod = @import("../mm/mmap.zig");

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
pub fn execve(path: []const u8, argv: []const []const u8, envp: []const []const u8) ExecError!noreturn {
    const proc = process.currentProcess() orelse return ExecError.NoProcess;

    var path_buf: [process.cwd_max_len]u8 = undefined;
    const resolved_path = process.resolvePath(proc, path, &path_buf) catch return ExecError.PathTooLong;

    var arg_bufs: [user_loader.max_argv][user_loader.max_string_len]u8 = undefined;
    var argv_copy: [user_loader.max_argv][]const u8 = undefined;
    if (argv.len > argv_copy.len) return ExecError.PathTooLong;
    for (argv, 0..) |arg, i| {
        if (arg.len >= arg_bufs[0].len) return ExecError.PathTooLong;
        @memcpy(arg_bufs[i][0..arg.len], arg);
        argv_copy[i] = arg_bufs[i][0..arg.len];
    }
    const argv_slice = argv_copy[0..argv.len];

    var env_bufs: [user_loader.max_envp][user_loader.max_string_len]u8 = undefined;
    var envp_copy: [user_loader.max_envp][]const u8 = undefined;
    if (envp.len > envp_copy.len) return ExecError.PathTooLong;
    for (envp, 0..) |entry, i| {
        if (entry.len >= env_bufs[0].len) return ExecError.PathTooLong;
        @memcpy(env_bufs[i][0..entry.len], entry);
        envp_copy[i] = env_bufs[i][0..entry.len];
    }
    const envp_slice = envp_copy[0..envp.len];

    const image_buf = programs.load(resolved_path) catch |err| switch (err) {
        programs.LoadError.NotFound => return ExecError.NotFound,
        programs.LoadError.NotFile => return ExecError.NotFile,
        programs.LoadError.PathTooLong => return ExecError.PathTooLong,
        programs.LoadError.OutOfMemory => return ExecError.OutOfMemory,
        programs.LoadError.TooLarge => return ExecError.InvalidElf,
        programs.LoadError.NotReady, programs.LoadError.IoError => return ExecError.IoError,
    };
    defer programs.free(image_buf);

    // Build the replacement image and VMA table before touching the current
    // address space. A failed execve must return to the old program intact.
    var replacement = process.AddressSpace.create() catch return ExecError.OutOfMemory;
    errdefer replacement.destroy();
    const loaded = user_loader.load(replacement.cr3, image_buf, argv_slice, envp_slice) catch return ExecError.InvalidElf;
    const new_vmas = process.buildLoadedVmas(&loaded) catch return ExecError.OutOfMemory;

    // Point of no return: swap atomically; nothing after this may fail and return.
    mmap_mod.releaseFileCachePins(proc);
    var previous = proc.address_space;
    proc.address_space = replacement;
    proc.vmas = new_vmas;
    previous.destroy();
    signal_mod.resetOnExec(proc);
    proc.brk = process.user_brk_base;

    const self = thread.currentThread() orelse thread.exit();
    const kstack = (@intFromPtr(self.stack) + self.stack_size) & ~@as(u64, 15);
    process.enterUser(proc, loaded, kstack);
}
