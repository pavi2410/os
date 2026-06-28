const numbers = @import("numbers.zig");
const process = @import("../proc/process.zig");
const thread = @import("../proc/thread.zig");
const tty = @import("../drivers/tty.zig");
const user_fork = @import("../proc/fork.zig");
const user_fork_ctx = @import("../proc/user_fork.zig");
const user_exec = @import("../proc/exec.zig");
const user_wait = @import("../proc/wait.zig");
const vfs = @import("../fs/vfs.zig");

/// Matches the stack layout built by `syscall_entry` (callee-saved pushed first).
pub const Frame = extern struct {
    r15: u64,
    r14: u64,
    r13: u64,
    r12: u64,
    rbp: u64,
    rbx: u64,
    arg5: u64,
    arg4: u64,
    arg3: u64,
    arg2: u64,
    arg1: u64,
    arg0: u64,
    nr: u64,
    user_rip: u64,
    user_rflags: u64,
    user_rsp: u64,
};

const ENOSYS: i64 = -38;
const EBADF: i64 = -9;
const EINVAL: i64 = -22;
const ENOENT: i64 = -2;
const EISDIR: i64 = -21;
const EMFILE: i64 = -24;
const EFAULT: i64 = -14;

pub export fn syscall_dispatch(frame: *Frame) callconv(.{ .x86_64_sysv = .{} }) i64 {
    return switch (frame.nr) {
        numbers.read => sysRead(frame.arg0, frame.arg1, frame.arg2),
        numbers.write => sysWrite(frame.arg0, frame.arg1, frame.arg2),
        numbers.open => sysOpen(frame.arg0, frame.arg1, frame.arg2),
        numbers.close => sysClose(frame.arg0),
        numbers.stat => sysStat(frame.arg0, frame.arg1),
        numbers.lseek => sysLseek(frame.arg0, @bitCast(@as(i64, @intCast(frame.arg1))), @truncate(frame.arg2)),
        numbers.brk => sysBrk(frame.arg0),
        numbers.getpid => sysGetpid(),
        numbers.fork => sysFork(frame),
        numbers.execve => sysExecve(frame.arg0, frame.arg1, frame.arg2),
        numbers.wait4 => sysWait4(frame.arg0, frame.arg1, frame.arg2, frame.arg3),
        numbers.unlink => sysUnlink(frame.arg0),
        numbers.mkdir => sysMkdir(frame.arg0, frame.arg1),
        numbers.rmdir => sysRmdir(frame.arg0),
        numbers.getdents64 => sysGetdents64(frame.arg0, frame.arg1, frame.arg2),
        numbers.exit, numbers.exit_group => sysExit(frame.arg0),
        else => ENOSYS,
    };
}

fn sysRead(fd: u64, buf_ptr: u64, count: u64) i64 {
    if (count == 0) return 0;
    const max_len: usize = 4096;
    const len: usize = @intCast(@min(count, max_len));
    const buf: [*]u8 = @ptrFromInt(buf_ptr);

    const proc = process.currentProcess() orelse return EBADF;
    if (fd >= process.max_fds) return EBADF;
    const slot = &proc.fds.fds[@intCast(fd)];

    return switch (slot.kind) {
        .console => {
            if (fd != 0) return EBADF;
            const read_len = tty.get().read(buf[0..len]) catch |err| switch (err) {
                tty.TtyError.WouldBlock => return -4,
            };
            return @intCast(read_len);
        },
        .file => {
            const n = vfs.read(slot.vfs_handle, buf[0..len]) catch return errnoFromVfs();
            return @intCast(n);
        },
        .none => EBADF,
    };
}

const EACCES: i64 = -13;

fn sysWrite(fd: u64, buf_ptr: u64, count: u64) i64 {
    if (count == 0) return 0;

    const max_len: usize = 4096;
    const len: usize = @intCast(@min(count, max_len));
    const buf: [*]const u8 = @ptrFromInt(buf_ptr);

    if (fd == 1 or fd == 2) {
        const written = tty.get().write(buf[0..len]);
        return @intCast(written);
    }

    const proc = process.currentProcess() orelse return EBADF;
    if (fd >= process.max_fds) return EBADF;
    const slot = &proc.fds.fds[@intCast(fd)];

    return switch (slot.kind) {
        .file => {
            const n = vfs.write(slot.vfs_handle, buf[0..len]) catch |err| return errnoFromVfsErr(err);
            return @intCast(n);
        },
        .console, .none => EBADF,
    };
}

fn sysOpen(path_ptr: u64, flags: u64, mode: u64) i64 {
    _ = mode;
    const path = userCString(path_ptr) orelse return EFAULT;
    const proc = process.currentProcess() orelse return EBADF;

    const O_ACCMODE: u64 = 0o3;
    const O_WRONLY: u64 = 0o1;
    const O_CREAT: u64 = 0o100;
    const O_TRUNC: u64 = 0o1000;
    const O_APPEND: u64 = 0o2000;

    const accmode = flags & O_ACCMODE;
    const open_flags: vfs.OpenFlags = .{
        .read = accmode != O_WRONLY,
        .write = accmode != 0, // O_RDONLY=0, O_WRONLY=1, O_RDWR=2
        .create = flags & O_CREAT != 0,
        .truncate = flags & O_TRUNC != 0,
        .append = flags & O_APPEND != 0,
    };

    const handle = vfs.open(path, open_flags) catch |err| return errnoFromVfsErr(err);
    const fd = proc.fds.allocFd() orelse {
        vfs.close(handle);
        return EMFILE;
    };
    proc.fds.fds[fd] = .{ .kind = .file, .vfs_handle = handle };
    return @intCast(fd);
}

fn sysClose(fd: u64) i64 {
    const proc = process.currentProcess() orelse return EBADF;
    if (fd >= process.max_fds) return EBADF;
    const slot = &proc.fds.fds[@intCast(fd)];
    if (slot.kind == .none) return EBADF;
    if (slot.kind == .file) vfs.close(slot.vfs_handle);
    slot.* = .{};
    return 0;
}

fn sysStat(path_ptr: u64, stat_ptr: u64) i64 {
    const path = userCString(path_ptr) orelse return EFAULT;
    if (stat_ptr == 0) return EFAULT;
    const out: *vfs.Stat = @ptrFromInt(stat_ptr);
    vfs.stat(path, out) catch |err| return errnoFromVfsErr(err);
    return 0;
}

fn sysLseek(fd: u64, offset: i64, whence: u32) i64 {
    const proc = process.currentProcess() orelse return EBADF;
    if (fd >= process.max_fds) return EBADF;
    const slot = &proc.fds.fds[@intCast(fd)];
    if (slot.kind != .file) return EBADF;
    const pos = vfs.lseek(slot.vfs_handle, offset, @enumFromInt(whence)) catch |err| return errnoFromVfsErr(err);
    return @bitCast(@as(i64, @intCast(pos)));
}

fn sysBrk(addr: u64) i64 {
    const proc = process.currentProcess() orelse return -1;
    return process.sysBrk(proc, addr);
}

fn sysGetpid() i64 {
    const proc = process.currentProcess() orelse return 1;
    return @intCast(proc.id);
}

fn sysFork(frame: *Frame) i64 {
    const ctx = user_fork_ctx.ForkUserContext.captureFromFrame(frame.*);
    return user_fork.forkFromSyscall(ctx);
}

fn sysExecve(path_ptr: u64, argv_ptr: u64, envp_ptr: u64) i64 {
    _ = argv_ptr;
    _ = envp_ptr;
    const path = userCString(path_ptr) orelse return EFAULT;
    user_exec.execve(path) catch |err| return errnoFromExecErr(err);
    unreachable;
}

fn errnoFromExecErr(err: user_exec.ExecError) i64 {
    return switch (err) {
        user_exec.ExecError.NotFound => ENOENT,
        user_exec.ExecError.NotFile => EINVAL,
        user_exec.ExecError.PathTooLong => EINVAL,
        user_exec.ExecError.InvalidElf => ENOENT,
        user_exec.ExecError.OutOfMemory => -12,
        user_exec.ExecError.IoError => -5,
        user_exec.ExecError.NoProcess => -1,
    };
}

fn sysWait4(pid: u64, status_ptr: u64, options: u64, rusage_ptr: u64) i64 {
    _ = rusage_ptr;
    const parent = process.currentProcess() orelse return -1;
    return user_wait.wait4(parent, @bitCast(pid), status_ptr, @truncate(options));
}

fn sysUnlink(path_ptr: u64) i64 {
    const path = userCString(path_ptr) orelse return EFAULT;
    vfs.unlink(path) catch |err| return errnoFromVfsErr(err);
    return 0;
}

fn sysMkdir(path_ptr: u64, mode: u64) i64 {
    _ = mode;
    const path = userCString(path_ptr) orelse return EFAULT;
    vfs.mkdir(path) catch |err| return errnoFromVfsErr(err);
    return 0;
}

fn sysRmdir(path_ptr: u64) i64 {
    const path = userCString(path_ptr) orelse return EFAULT;
    vfs.rmdir(path) catch |err| return errnoFromVfsErr(err);
    return 0;
}

fn sysGetdents64(fd: u64, buf_ptr: u64, count: u64) i64 {
    if (buf_ptr == 0 or count == 0) return EINVAL;

    const proc = process.currentProcess() orelse return EBADF;
    if (fd >= process.max_fds) return EBADF;
    const slot = &proc.fds.fds[@intCast(fd)];
    if (slot.kind != .file) return EBADF;

    const max_len: usize = 4096;
    const cap_len: usize = @intCast(@min(count, max_len));

    var kbuf: [4096]u8 = undefined;
    const n = vfs.getdents64(slot.vfs_handle, kbuf[0..cap_len]) catch |err| return errnoFromVfsErr(err);

    const user_buf: [*]u8 = @ptrFromInt(buf_ptr);
    @memcpy(user_buf[0..n], kbuf[0..n]);
    return @intCast(n);
}

fn sysExit(status: u64) i64 {
    if (process.currentProcess() != null) {
        process.terminateCurrent(@truncate(status));
    }
    thread.exit();
}

fn errnoFromVfs() i64 {
    return -5; // EIO
}

fn errnoFromVfsErr(err: vfs.VfsError) i64 {
    return switch (err) {
        vfs.VfsError.NotFound => ENOENT,
        vfs.VfsError.IsDirectory => EISDIR,
        vfs.VfsError.BadHandle => EBADF,
        vfs.VfsError.TooManyOpenFiles => EMFILE,
        vfs.VfsError.InvalidWhence => EINVAL,
        vfs.VfsError.NotReady, vfs.VfsError.IoError => -5,
        vfs.VfsError.InvalidBpb => -5,
        vfs.VfsError.NotFile => EINVAL,
        vfs.VfsError.NameTooLong, vfs.VfsError.PathTooLong => EINVAL,
        vfs.VfsError.BufferTooSmall => EINVAL,
        vfs.VfsError.Exists => -17, // EEXIST
        vfs.VfsError.NoSpace => -28, // ENOSPC
        vfs.VfsError.NotEmpty => -39, // ENOTEMPTY
        vfs.VfsError.ReadOnly => EACCES,
    };
}

fn userCString(ptr: u64) ?[]const u8 {
    if (ptr == 0) return null;
    const start: [*]const u8 = @ptrFromInt(ptr);
    var len: usize = 0;
    while (len < 256) : (len += 1) {
        if (start[len] == 0) return start[0..len];
    }
    return null;
}
