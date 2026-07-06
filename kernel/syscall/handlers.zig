const numbers = @import("numbers.zig");
const process = @import("../proc/process.zig");
const thread = @import("../proc/thread.zig");
const user_fork = @import("../proc/fork.zig");
const user_fork_ctx = @import("../proc/user_fork.zig");
const user_exec = @import("../proc/exec.zig");
const user_wait = @import("../proc/wait.zig");
const vfs = @import("../fs/vfs.zig");
const socket = @import("../net/socket.zig");
const net_info = @import("../net/info.zig");
const hal = @import("../hal.zig");
const abi_fs = @import("abi_fs");
const abi_syscall = @import("abi_syscall");
const errno = @import("errno.zig");
const fdtab = @import("fd.zig");
const fd_ops = @import("fd_ops.zig");
const user = @import("user.zig");

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
        numbers.clock_gettime => sysClockGettime(frame.arg0, frame.arg1),
        numbers.socket => sysSocket(frame.arg0, frame.arg1, frame.arg2),
        numbers.connect => sysConnect(frame.arg0, frame.arg1, frame.arg2),
        numbers.sendto => sysSendto(frame.arg0, frame.arg1, frame.arg2, frame.arg3, frame.arg4, frame.arg5),
        numbers.recvfrom => sysRecvfrom(frame.arg0, frame.arg1, frame.arg2, frame.arg3, frame.arg4, frame.arg5),
        numbers.send => sysSend(frame.arg0, frame.arg1, frame.arg2, frame.arg3),
        numbers.recv => sysRecv(frame.arg0, frame.arg1, frame.arg2, frame.arg3),
        numbers.bind => sysBind(frame.arg0, frame.arg1, frame.arg2),
        numbers.getnetconfig => sysGetnetconfig(frame.arg0),
        numbers.getneighbors => sysGetneighbors(frame.arg0, frame.arg1),
        numbers.exit, numbers.exit_group => sysExit(frame.arg0),
        else => errno.ENOSYS,
    };
}

fn sysRead(fd: u64, buf_ptr: u64, count: u64) i64 {
    if (count == 0) return 0;
    const max_len: usize = 4096;
    const len: usize = @intCast(@min(count, max_len));
    const buf = user.bytes(buf_ptr, len) orelse return errno.EFAULT;

    const slot = fdtab.currentSlot(fd) catch return errno.EBADF;

    return fd_ops.read(fd, slot, buf);
}

fn sysWrite(fd: u64, buf_ptr: u64, count: u64) i64 {
    if (count == 0) return 0;

    const max_len: usize = 4096;
    const len: usize = @intCast(@min(count, max_len));
    const buf = user.constBytes(buf_ptr, len) orelse return errno.EFAULT;

    const slot = fdtab.currentSlot(fd) catch return errno.EBADF;
    return fd_ops.write(fd, slot, buf);
}

fn sysOpen(path_ptr: u64, flags: u64, mode: u64) i64 {
    _ = mode;
    const path = user.cString(path_ptr, 256) orelse return errno.EFAULT;
    const proc = fdtab.currentProcess() catch return errno.EBADF;

    const accmode = flags & abi_fs.O_ACCMODE;
    const open_flags: vfs.OpenFlags = .{
        .read = accmode != abi_fs.O_WRONLY,
        .write = accmode != 0, // O_RDONLY=0, O_WRONLY=1, O_RDWR=2
        .create = flags & abi_fs.O_CREAT != 0,
        .truncate = flags & abi_fs.O_TRUNC != 0,
        .append = flags & abi_fs.O_APPEND != 0,
    };

    const handle = vfs.open(path, open_flags) catch |err| return errno.fromVfs(err);
    const fd = fdtab.alloc(proc) catch {
        vfs.close(handle);
        return errno.EMFILE;
    };
    proc.fds.fds[fd] = .{ .kind = .file, .vfs_handle = handle };
    return @intCast(fd);
}

fn sysClose(fd: u64) i64 {
    const slot = fdtab.currentSlot(fd) catch return errno.EBADF;
    return fd_ops.close(slot);
}

fn sysStat(path_ptr: u64, stat_ptr: u64) i64 {
    const path = user.cString(path_ptr, 256) orelse return errno.EFAULT;
    const out = user.outPtr(vfs.Stat, stat_ptr) orelse return errno.EFAULT;
    vfs.stat(path, out) catch |err| return errno.fromVfs(err);
    return 0;
}

fn sysLseek(fd: u64, offset: i64, whence: u32) i64 {
    const slot = fdtab.expectFile(fd) catch return errno.EBADF;
    return fd_ops.lseek(slot, offset, whence);
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
    _ = envp_ptr;
    const path = user.cString(path_ptr, 256) orelse return errno.EFAULT;
    var argv_buf: [16][]const u8 = undefined;
    const argv_count = user.readArgv(argv_ptr, &argv_buf, 256) catch return errno.EFAULT;
    user_exec.execve(path, argv_buf[0..argv_count]) catch |err| return errno.fromExec(err);
    unreachable;
}

fn sysWait4(pid: u64, status_ptr: u64, options: u64, rusage_ptr: u64) i64 {
    _ = rusage_ptr;
    const parent = process.currentProcess() orelse return -1;
    return user_wait.wait4(parent, @bitCast(pid), status_ptr, @truncate(options));
}

fn sysUnlink(path_ptr: u64) i64 {
    const path = user.cString(path_ptr, 256) orelse return errno.EFAULT;
    vfs.unlink(path) catch |err| return errno.fromVfs(err);
    return 0;
}

fn sysMkdir(path_ptr: u64, mode: u64) i64 {
    _ = mode;
    const path = user.cString(path_ptr, 256) orelse return errno.EFAULT;
    vfs.mkdir(path) catch |err| return errno.fromVfs(err);
    return 0;
}

fn sysRmdir(path_ptr: u64) i64 {
    const path = user.cString(path_ptr, 256) orelse return errno.EFAULT;
    vfs.rmdir(path) catch |err| return errno.fromVfs(err);
    return 0;
}

fn sysGetdents64(fd: u64, buf_ptr: u64, count: u64) i64 {
    if (buf_ptr == 0 or count == 0) return errno.EINVAL;

    const slot = fdtab.expectFile(fd) catch return errno.EBADF;

    const max_len: usize = 4096;
    const cap_len: usize = @intCast(@min(count, max_len));

    var kbuf: [4096]u8 = undefined;
    const n = fd_ops.getdents64(slot, kbuf[0..cap_len]);
    if (n < 0) return n;
    const bytes: usize = @intCast(n);

    const user_buf = user.bytes(buf_ptr, bytes) orelse return errno.EFAULT;
    @memcpy(user_buf, kbuf[0..bytes]);
    return @intCast(n);
}

const Timespec = extern struct {
    tv_sec: i64,
    tv_nsec: i64,
};

fn sysClockGettime(clock_id: u64, timespec_ptr: u64) i64 {
    if (timespec_ptr == 0) return errno.EFAULT;
    var ts: Timespec = .{ .tv_sec = 0, .tv_nsec = 0 };
    switch (clock_id) {
        abi_syscall.CLOCK_REALTIME => {
            ts.tv_sec = hal.clock.realtimeSeconds();
        },
        abi_syscall.CLOCK_MONOTONIC => {
            const ticks = hal.clock.timerTickCount();
            ts.tv_sec = @intCast(@divTrunc(ticks, 100));
            ts.tv_nsec = @intCast(@mod(ticks, 100) * 10_000_000);
        },
        else => return errno.EINVAL,
    }
    const user_buf = user.bytes(timespec_ptr, @sizeOf(Timespec)) orelse return errno.EFAULT;
    @memcpy(user_buf, @as([*]const u8, @ptrCast(&ts))[0..@sizeOf(Timespec)]);
    return 0;
}

fn sysSocket(domain: u64, sock_type: u64, protocol: u64) i64 {
    const handle = socket.create(@truncate(domain), @truncate(sock_type), @intCast(protocol)) catch |err| {
        return errno.fromSocket(err);
    };
    const proc = fdtab.currentProcess() catch return errno.EBADF;
    const fd = fdtab.alloc(proc) catch return errno.EMFILE;
    proc.fds.fds[fd] = .{ .kind = .socket, .socket_handle = handle };
    return @intCast(fd);
}

fn sysBind(sockfd: u64, addr_ptr: u64, addrlen: u64) i64 {
    _ = addrlen;
    const slot = fdtab.expectSocket(sockfd) catch return errno.EBADF;
    const addr = user.value(socket.SockaddrIn, addr_ptr) orelse return errno.EFAULT;
    socket.bind(slot.socket_handle, &addr) catch |err| return errno.fromSocket(err);
    return 0;
}

fn sysConnect(sockfd: u64, addr_ptr: u64, addrlen: u64) i64 {
    _ = addrlen;
    const slot = fdtab.expectSocket(sockfd) catch return errno.EBADF;
    const addr = user.value(socket.SockaddrIn, addr_ptr) orelse return errno.EFAULT;
    socket.connect(slot.socket_handle, &addr) catch |err| return errno.fromSocket(err);
    return 0;
}

fn sysSend(sockfd: u64, buf_ptr: u64, len: u64, flags: u64) i64 {
    _ = flags;
    if (len == 0) return 0;
    const slot = fdtab.expectSocket(sockfd) catch return errno.EBADF;
    const max_len: usize = 4096;
    const copy_len: usize = @intCast(@min(len, max_len));
    const buf = user.constBytes(buf_ptr, copy_len) orelse return errno.EFAULT;
    const sent = socket.send(slot.socket_handle, buf) catch |err| {
        return errno.fromSocket(err);
    };
    return @intCast(sent);
}

fn sysRecv(sockfd: u64, buf_ptr: u64, len: u64, flags: u64) i64 {
    _ = flags;
    if (len == 0) return 0;
    const slot = fdtab.expectSocket(sockfd) catch return errno.EBADF;
    const max_len: usize = 4096;
    const copy_len: usize = @intCast(@min(len, max_len));
    const buf = user.bytes(buf_ptr, copy_len) orelse return errno.EFAULT;
    const received = socket.recv(slot.socket_handle, buf, 2_000_000) catch |err| {
        return errno.fromSocket(err);
    };
    return @intCast(received);
}

fn sysSendto(sockfd: u64, buf_ptr: u64, len: u64, flags: u64, dest_ptr: u64, addrlen: u64) i64 {
    _ = flags;
    _ = addrlen;
    const slot = fdtab.expectSocket(sockfd) catch return errno.EBADF;
    const dest = user.value(socket.SockaddrIn, dest_ptr) orelse return errno.EFAULT;
    const max_len: usize = 4096;
    const copy_len: usize = @intCast(@min(len, max_len));
    const buf = user.constBytes(buf_ptr, copy_len) orelse return errno.EFAULT;
    const sent = socket.sendto(slot.socket_handle, buf, &dest) catch |err| {
        return errno.fromSocket(err);
    };
    return @intCast(sent);
}

fn sysRecvfrom(sockfd: u64, buf_ptr: u64, len: u64, flags: u64, src_ptr: u64, addrlen_ptr: u64) i64 {
    _ = flags;
    if (len == 0) return 0;
    const slot = fdtab.expectSocket(sockfd) catch return errno.EBADF;
    const max_len: usize = 4096;
    const copy_len: usize = @intCast(@min(len, max_len));
    const buf = user.bytes(buf_ptr, copy_len) orelse return errno.EFAULT;

    var src: socket.SockaddrIn = undefined;
    const src_out: ?*socket.SockaddrIn = if (src_ptr != 0) &src else null;
    const received = socket.recvfrom(slot.socket_handle, buf, src_out, 2_000_000) catch |err| {
        return errno.fromSocket(err);
    };

    if (src_ptr != 0) {
        (user.outPtr(socket.SockaddrIn, src_ptr) orelse return errno.EFAULT).* = src;
        if (addrlen_ptr != 0) {
            (user.outPtr(u32, addrlen_ptr) orelse return errno.EFAULT).* = @sizeOf(socket.SockaddrIn);
        }
    }
    return @intCast(received);
}

fn sysGetnetconfig(buf_ptr: u64) i64 {
    const out = user.outPtr(net_info.NetConfig, buf_ptr) orelse return errno.EFAULT;
    net_info.fillConfig(out);
    return 0;
}

fn sysGetneighbors(buf_ptr: u64, max: u64) i64 {
    if (buf_ptr == 0 or max == 0) return errno.EINVAL;
    const cap: usize = @intCast(@min(max, 64));
    const out = user.slice(net_info.NeighEntry, buf_ptr, cap) orelse return errno.EFAULT;
    const count = net_info.fillNeighbors(out);
    return @intCast(count);
}

fn sysExit(status: u64) i64 {
    if (process.currentProcess() != null) {
        process.terminateCurrent(@truncate(status));
    }
    thread.exit();
}

