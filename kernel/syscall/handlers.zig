const numbers = @import("numbers.zig");
const process = @import("../proc/process.zig");
const serial = @import("../arch/x86_64/serial.zig");
const thread = @import("../proc/thread.zig");
const tty = @import("../drivers/tty.zig");
const user_spawn = @import("../proc/user_spawn.zig");
const vfs = @import("../fs/vfs.zig");

/// Matches the stack layout built by `syscall_entry` (r9 pushed first).
pub const Frame = extern struct {
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
        numbers.spawn => sysSpawn(frame.arg0),
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

fn sysWrite(fd: u64, buf_ptr: u64, count: u64) i64 {
    if (fd != 1 and fd != 2) return EBADF;
    if (count == 0) return 0;

    const max_len: usize = 4096;
    const len: usize = @intCast(@min(count, max_len));
    const buf: [*]const u8 = @ptrFromInt(buf_ptr);
    const written = tty.get().write(buf[0..len]);
    return @intCast(written);
}

fn sysOpen(path_ptr: u64, flags: u64, mode: u64) i64 {
    _ = flags;
    _ = mode;
    const path = userCString(path_ptr) orelse return EFAULT;
    const proc = process.currentProcess() orelse return EBADF;

    const handle = vfs.open(path) catch |err| return errnoFromVfsErr(err);
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

fn sysSpawn(path_ptr: u64) i64 {
    const path = userCString(path_ptr) orelse return EFAULT;
    return user_spawn.spawn(path);
}

fn sysExit(status: u64) i64 {
    if (process.currentProcess() != null) {
        user_spawn.onChildExit(@truncate(status));
        process.terminateCurrent(@truncate(status));
    }
    serial.printf("\r\nsyscall exit({d})\r\n", .{status});
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
