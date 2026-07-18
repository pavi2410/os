const numbers = @import("numbers.zig");
const process = @import("../proc/process.zig");
const scheduler = @import("../proc/scheduler.zig");
const thread = @import("../proc/thread.zig");
const user_fork = @import("../proc/fork.zig");
const user_mode = @import("../arch/x86_64/user.zig");
const user_exec = @import("../proc/exec.zig");
const user_wait = @import("../proc/wait.zig");
const vfs = @import("../fs/vfs.zig");
const devfs = @import("../fs/devfs.zig");
const socket = @import("../net/socket.zig");
const net_info = @import("../net/info.zig");
const hal = @import("../hal.zig");
const pipe = @import("../ipc/pipe.zig");
const runtime = @import("../runtime.zig");
const mmap_sys = @import("../mm/mmap.zig");
const abi_fs = @import("abi_fs");
const abi_signal = @import("abi_signal");
const abi_syscall = @import("abi_syscall");
const errno = @import("errno.zig");
const fdtab = @import("fd.zig");
const fd_ops = @import("fd_ops.zig");
const fd_retain = @import("../proc/fd_retain.zig");
const signal = @import("../proc/signal.zig");
const user = @import("user.zig");
const copy_out = @import("copy_out.zig");
const cpu = @import("../arch/x86_64/cpu.zig");
const std = @import("std");

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
    const ret = dispatchSyscall(frame);
    if (process.currentProcess()) |proc| {
        signal.tryApply(proc);
    }
    // Syscalls run with IF cleared (SFMASK). Briefly open IF so a sticky
    // quantum that expired during a blocking sti window can be honored before
    // returning to user. Pure user CPU is preempted by the timer IRQ path.
    cpu.sti();
    scheduler.yieldIfRequested();
    cpu.cli();
    return ret;
}

fn dispatchSyscall(frame: *Frame) i64 {
    return switch (frame.nr) {
        numbers.read => sysRead(frame.arg0, frame.arg1, frame.arg2),
        numbers.write => sysWrite(frame.arg0, frame.arg1, frame.arg2),
        numbers.open => sysOpen(frame.arg0, frame.arg1, frame.arg2),
        numbers.close => sysClose(frame.arg0),
        numbers.stat => sysStat(frame.arg0, frame.arg1),
        numbers.lseek => sysLseek(frame.arg0, @bitCast(@as(i64, @intCast(frame.arg1))), @truncate(frame.arg2)),
        numbers.mmap => sysMmap(frame.arg0, frame.arg1, frame.arg2, frame.arg3, frame.arg4, frame.arg5),
        numbers.mprotect => sysMprotect(frame.arg0, frame.arg1, frame.arg2),
        numbers.munmap => sysMunmap(frame.arg0, frame.arg1),
        numbers.brk => sysBrk(frame.arg0),
        numbers.rt_sigaction => sysRtSigaction(frame.arg0, frame.arg1, frame.arg2, frame.arg3),
        numbers.rt_sigprocmask => sysRtSigprocmask(frame.arg0, frame.arg1, frame.arg2, frame.arg3),
        numbers.pipe => sysPipe(frame.arg0),
        numbers.sched_yield => sysSchedYield(),
        numbers.dup => sysDup(frame.arg0),
        numbers.dup2 => sysDup2(frame.arg0, frame.arg1),
        numbers.getpid => sysGetpid(),
        numbers.fsync => sysFsync(frame.arg0),
        numbers.fork => sysFork(frame),
        numbers.execve => sysExecve(frame.arg0, frame.arg1, frame.arg2),
        numbers.wait4 => sysWait4(frame.arg0, frame.arg1, frame.arg2, frame.arg3),
        numbers.kill => sysKill(frame.arg0, frame.arg1),
        numbers.getcwd => sysGetcwd(frame.arg0, frame.arg1),
        numbers.chdir => sysChdir(frame.arg0),
        numbers.unlink => sysUnlink(frame.arg0),
        numbers.rename => sysRename(frame.arg0, frame.arg1),
        numbers.mkdir => sysMkdir(frame.arg0, frame.arg1),
        numbers.rmdir => sysRmdir(frame.arg0),
        numbers.symlink => sysSymlink(frame.arg0, frame.arg1),
        numbers.readlink => sysReadlink(frame.arg0, frame.arg1, frame.arg2),
        numbers.mount => sysMount(frame.arg0, frame.arg1, frame.arg2, frame.arg3, frame.arg4),
        numbers.umount2 => sysUmount2(frame.arg0, frame.arg1),
        numbers.reboot => sysReboot(frame.arg0, frame.arg1, frame.arg2, frame.arg3),
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

fn resolvePathArg(path: []const u8, buf: []u8) ?[]const u8 {
    const proc = process.currentProcess() orelse return path;
    return process.resolvePath(proc, path, buf) catch null;
}

fn sysOpen(path_ptr: u64, flags: u64, mode: u64) i64 {
    _ = mode;
    const path_raw = user.cString(path_ptr, 256) orelse return errno.EFAULT;
    var path_buf: [process.cwd_max_len]u8 = undefined;
    const path = resolvePathArg(path_raw, &path_buf) orelse return errno.EFAULT;
    const proc = fdtab.currentProcess() catch return errno.EBADF;

    const accmode = abi_fs.AccMode.fromFlags(@truncate(flags)) orelse return errno.EINVAL;
    const open_flags: vfs.OpenFlags = .{
        .read = accmode != .wronly,
        .write = accmode != .rdonly,
        .create = flags & abi_fs.O_CREAT != 0,
        .truncate = flags & abi_fs.O_TRUNC != 0,
        .append = flags & abi_fs.O_APPEND != 0,
    };

    if (devfs.lookup(path)) |node| {
        switch (node) {
            .device => |dev| {
                if (!open_flags.read and !open_flags.write) return errno.EINVAL;
                const fd = fdtab.alloc(proc) catch return errno.EMFILE;
                proc.fds.fds[fd] = .{ .device = .{
                    .kind = dev,
                    .readable = open_flags.read,
                    .writable = open_flags.write,
                } };
                return @intCast(fd);
            },
            .root => {},
        }
    }

    const handle = runtime.boot().vfs.open(path, open_flags) catch |err| return errno.fromVfs(err);
    const fd = fdtab.alloc(proc) catch {
        runtime.boot().vfs.close(handle);
        return errno.EMFILE;
    };
    proc.fds.fds[fd] = .{ .file = handle };
    return @intCast(fd);
}

fn sysClose(fd: u64) i64 {
    const slot = fdtab.currentSlot(fd) catch return errno.EBADF;
    return fd_ops.close(slot);
}

fn sysStat(path_ptr: u64, stat_ptr: u64) i64 {
    const path_raw = user.cString(path_ptr, 256) orelse return errno.EFAULT;
    var path_buf: [process.cwd_max_len]u8 = undefined;
    const path = resolvePathArg(path_raw, &path_buf) orelse return errno.EFAULT;
    const out = user.outPtr(vfs.Stat, stat_ptr) orelse return errno.EFAULT;
    runtime.boot().vfs.stat(path, out) catch |err| return errno.fromVfs(err);
    return 0;
}

fn sysLseek(fd: u64, offset: i64, whence: u32) i64 {
    const slot = fdtab.currentSlot(fd) catch return errno.EBADF;
    return fd_ops.lseek(slot, offset, whence);
}

fn sysMmap(addr: u64, len: u64, prot: u64, flags: u64, fd: u64, offset: u64) i64 {
    const proc = process.currentProcess() orelse return errno.ENOMEM;
    return mmap_sys.sysMmap(proc, addr, len, prot, flags, fd, offset);
}

fn sysMprotect(addr: u64, len: u64, prot: u64) i64 {
    const proc = process.currentProcess() orelse return errno.ENOMEM;
    return mmap_sys.sysMprotect(proc, addr, len, prot);
}

fn sysMunmap(addr: u64, len: u64) i64 {
    const proc = process.currentProcess() orelse return errno.ENOMEM;
    return mmap_sys.sysMunmap(proc, addr, len);
}

fn sysBrk(addr: u64) i64 {
    const proc = process.currentProcess() orelse return -1;
    return process.sysBrk(proc, addr);
}

fn sysGetpid() i64 {
    const proc = process.currentProcess() orelse return 1;
    return @intCast(proc.id);
}

fn sysSchedYield() i64 {
    scheduler.yield();
    return 0;
}

fn sysFsync(fd: u64) i64 {
    const slot = fdtab.currentSlot(fd) catch return errno.EBADF;
    return switch (slot.*) {
        .file => |handle| {
            runtime.boot().vfs.fsync(handle) catch |err| return errno.fromVfs(err);
            return 0;
        },
        else => errno.EINVAL,
    };
}

fn sysFork(frame: *Frame) i64 {
    const ctx = user_mode.ForkContext.captureFromSyscallFrame(frame.*);
    return user_fork.forkFromSyscall(ctx);
}

fn sysExecve(path_ptr: u64, argv_ptr: u64, envp_ptr: u64) i64 {
    const path = user.cString(path_ptr, 256) orelse return errno.EFAULT;
    var argv_buf: [16][]const u8 = undefined;
    const argv_count = user.readArgv(argv_ptr, &argv_buf, 256) catch return errno.EFAULT;
    var envp_buf: [16][]const u8 = undefined;
    const envp_count = user.readEnvp(envp_ptr, &envp_buf, 256) catch return errno.EFAULT;
    user_exec.execve(path, argv_buf[0..argv_count], envp_buf[0..envp_count]) catch |err| return errno.fromExec(err);
    unreachable;
}

fn sysWait4(pid: u64, status_ptr: u64, options: u64, rusage_ptr: u64) i64 {
    _ = rusage_ptr;
    const parent = process.currentProcess() orelse return -1;
    return user_wait.wait4(parent, @bitCast(pid), status_ptr, @truncate(options));
}

fn sysGetcwd(buf_ptr: u64, size: u64) i64 {
    if (buf_ptr == 0 or size == 0) return errno.EINVAL;
    const proc = process.currentProcess() orelse return errno.EPERM;
    const cwd = process.cwdSlice(proc);
    if (size < cwd.len + 1) return errno.ERANGE;
    const buf = user.bytes(buf_ptr, cwd.len + 1) orelse return errno.EFAULT;
    @memcpy(buf[0..cwd.len], cwd);
    buf[cwd.len] = 0;
    return @intCast(cwd.len);
}

fn sysChdir(path_ptr: u64) i64 {
    const path_raw = user.cString(path_ptr, 256) orelse return errno.EFAULT;
    const proc = process.currentProcess() orelse return errno.EPERM;
    var path_buf: [process.cwd_max_len]u8 = undefined;
    const path = process.resolvePath(proc, path_raw, &path_buf) catch return errno.EINVAL;

    var st: vfs.Stat = .{};
    runtime.boot().vfs.stat(path, &st) catch |err| return errno.fromVfs(err);
    if (abi_fs.ModeType.fromMode(st.st_mode) != .dir) return errno.ENOTDIR;

    process.setCwd(proc, path) catch return errno.EINVAL;
    return 0;
}

fn sysUnlink(path_ptr: u64) i64 {
    const path_raw = user.cString(path_ptr, 256) orelse return errno.EFAULT;
    var path_buf: [process.cwd_max_len]u8 = undefined;
    const path = resolvePathArg(path_raw, &path_buf) orelse return errno.EFAULT;
    runtime.boot().vfs.unlink(path) catch |err| return errno.fromVfs(err);
    return 0;
}

fn sysRename(old_ptr: u64, new_ptr: u64) i64 {
    const old_raw = user.cString(old_ptr, 256) orelse return errno.EFAULT;
    const new_raw = user.cString(new_ptr, 256) orelse return errno.EFAULT;
    var old_buf: [process.cwd_max_len]u8 = undefined;
    var new_buf: [process.cwd_max_len]u8 = undefined;
    const old_path = resolvePathArg(old_raw, &old_buf) orelse return errno.EFAULT;
    const new_path = resolvePathArg(new_raw, &new_buf) orelse return errno.EFAULT;
    runtime.boot().vfs.rename(old_path, new_path) catch |err| return errno.fromVfs(err);
    return 0;
}

fn sysSymlink(target_ptr: u64, link_ptr: u64) i64 {
    const target = user.cString(target_ptr, 256) orelse return errno.EFAULT;
    const link_raw = user.cString(link_ptr, 256) orelse return errno.EFAULT;
    var link_buf: [process.cwd_max_len]u8 = undefined;
    const linkpath = resolvePathArg(link_raw, &link_buf) orelse return errno.EFAULT;
    runtime.boot().vfs.symlink(target, linkpath) catch |err| return errno.fromVfs(err);
    return 0;
}

fn sysReadlink(path_ptr: u64, buf_ptr: u64, bufsiz: u64) i64 {
    if (buf_ptr == 0 or bufsiz == 0) return errno.EINVAL;
    const path_raw = user.cString(path_ptr, 256) orelse return errno.EFAULT;
    var path_buf: [process.cwd_max_len]u8 = undefined;
    const path = resolvePathArg(path_raw, &path_buf) orelse return errno.EFAULT;
    const max_len: usize = 4096;
    const len: usize = @intCast(@min(bufsiz, max_len));
    var kbuf: [4096]u8 = undefined;
    const n = runtime.boot().vfs.readlink(path, kbuf[0..len]) catch |err| return errno.fromVfs(err);
    const out = user.bytes(buf_ptr, n) orelse return errno.EFAULT;
    @memcpy(out[0..n], kbuf[0..n]);
    return @intCast(n);
}

fn sysMkdir(path_ptr: u64, mode: u64) i64 {
    _ = mode;
    const path_raw = user.cString(path_ptr, 256) orelse return errno.EFAULT;
    var path_buf: [process.cwd_max_len]u8 = undefined;
    const path = resolvePathArg(path_raw, &path_buf) orelse return errno.EFAULT;
    runtime.boot().vfs.mkdir(path) catch |err| return errno.fromVfs(err);
    return 0;
}

fn sysRmdir(path_ptr: u64) i64 {
    const path_raw = user.cString(path_ptr, 256) orelse return errno.EFAULT;
    var path_buf: [process.cwd_max_len]u8 = undefined;
    const path = resolvePathArg(path_raw, &path_buf) orelse return errno.EFAULT;
    runtime.boot().vfs.rmdir(path) catch |err| return errno.fromVfs(err);
    return 0;
}

fn sysMount(source_ptr: u64, target_ptr: u64, fstype_ptr: u64, flags: u64, data_ptr: u64) i64 {
    _ = source_ptr;
    _ = flags;
    _ = data_ptr;
    const target_raw = user.cString(target_ptr, 256) orelse return errno.EFAULT;
    const fstype = user.cString(fstype_ptr, 32) orelse return errno.EFAULT;
    if (!std.mem.eql(u8, fstype, "tmpfs")) return errno.EINVAL;

    var path_buf: [process.cwd_max_len]u8 = undefined;
    const target = resolvePathArg(target_raw, &path_buf) orelse return errno.EFAULT;
    runtime.boot().vfs.mountTmpfs(target) catch |err| return errno.fromVfs(err);
    return 0;
}

fn sysUmount2(target_ptr: u64, flags: u64) i64 {
    _ = flags;
    const target_raw = user.cString(target_ptr, 256) orelse return errno.EFAULT;
    var path_buf: [process.cwd_max_len]u8 = undefined;
    const target = resolvePathArg(target_raw, &path_buf) orelse return errno.EFAULT;
    runtime.boot().vfs.umount(target) catch |err| return errno.fromVfs(err);
    return 0;
}

fn sysGetdents64(fd: u64, buf_ptr: u64, count: u64) i64 {
    if (buf_ptr == 0 or count == 0) return errno.EINVAL;

    const slot = fdtab.currentSlot(fd) catch return errno.EBADF;

    const max_len: usize = 4096;
    const cap_len: usize = @intCast(@min(count, max_len));

    // Validate the user buffer before advancing the directory cursor.
    if (user.bytes(buf_ptr, cap_len) == null) return errno.EFAULT;

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
    const handle = socket.create(&runtime.boot().network, @truncate(domain), @truncate(sock_type), @intCast(protocol)) catch |err| {
        return errno.fromSocket(err);
    };
    const proc = fdtab.currentProcess() catch {
        socket.close(&runtime.boot().network, handle);
        return errno.EBADF;
    };
    const fd = fdtab.alloc(proc) catch {
        socket.close(&runtime.boot().network, handle);
        return errno.EMFILE;
    };
    proc.fds.fds[fd] = .{ .socket = handle };
    return @intCast(fd);
}

fn sysBind(sockfd: u64, addr_ptr: u64, addrlen: u64) i64 {
    _ = addrlen;
    const handle = fdtab.expectSocket(sockfd) catch return errno.EBADF;
    const addr = user.value(socket.SockaddrIn, addr_ptr) orelse return errno.EFAULT;
    socket.bind(&runtime.boot().network, handle, &addr) catch |err| return errno.fromSocket(err);
    return 0;
}

fn sysConnect(sockfd: u64, addr_ptr: u64, addrlen: u64) i64 {
    _ = addrlen;
    const handle = fdtab.expectSocket(sockfd) catch return errno.EBADF;
    const addr = user.value(socket.SockaddrIn, addr_ptr) orelse return errno.EFAULT;
    socket.connect(&runtime.boot().network, handle, &addr) catch |err| return errno.fromSocket(err);
    return 0;
}

fn sysSend(sockfd: u64, buf_ptr: u64, len: u64, flags: u64) i64 {
    _ = flags;
    if (len == 0) return 0;
    const handle = fdtab.expectSocket(sockfd) catch return errno.EBADF;
    const max_len: usize = 4096;
    const copy_len: usize = @intCast(@min(len, max_len));
    const buf = user.constBytes(buf_ptr, copy_len) orelse return errno.EFAULT;
    const sent = socket.send(&runtime.boot().network, handle, buf) catch |err| {
        return errno.fromSocket(err);
    };
    return @intCast(sent);
}

fn sysRecv(sockfd: u64, buf_ptr: u64, len: u64, flags: u64) i64 {
    _ = flags;
    if (len == 0) return 0;
    const handle = fdtab.expectSocket(sockfd) catch return errno.EBADF;
    const max_len: usize = 4096;
    const copy_len: usize = @intCast(@min(len, max_len));
    const buf = user.bytes(buf_ptr, copy_len) orelse return errno.EFAULT;
    const received = socket.recv(&runtime.boot().network, handle, buf, 2_000_000) catch |err| {
        return errno.fromSocket(err);
    };
    return @intCast(received);
}

fn sysSendto(sockfd: u64, buf_ptr: u64, len: u64, flags: u64, dest_ptr: u64, addrlen: u64) i64 {
    _ = flags;
    _ = addrlen;
    const handle = fdtab.expectSocket(sockfd) catch return errno.EBADF;
    const dest = user.value(socket.SockaddrIn, dest_ptr) orelse return errno.EFAULT;
    const max_len: usize = 4096;
    const copy_len: usize = @intCast(@min(len, max_len));
    const buf = user.constBytes(buf_ptr, copy_len) orelse return errno.EFAULT;
    const sent = socket.sendto(&runtime.boot().network, handle, buf, &dest) catch |err| {
        return errno.fromSocket(err);
    };
    return @intCast(sent);
}

fn sysRecvfrom(sockfd: u64, buf_ptr: u64, len: u64, flags: u64, src_ptr: u64, addrlen_ptr: u64) i64 {
    _ = flags;
    if (len == 0) return 0;
    const handle = fdtab.expectSocket(sockfd) catch return errno.EBADF;
    const max_len: usize = 4096;
    const copy_len: usize = @intCast(@min(len, max_len));
    const buf = user.bytes(buf_ptr, copy_len) orelse return errno.EFAULT;

    var src: socket.SockaddrIn = undefined;
    const src_out: ?*socket.SockaddrIn = if (src_ptr != 0) &src else null;
    const received = socket.recvfrom(&runtime.boot().network, handle, buf, src_out, 2_000_000) catch |err| {
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

fn sysPipe(fd_ptr: u64) i64 {
    if (fd_ptr == 0) return errno.EFAULT;
    const out = user.outPtr([2]i32, fd_ptr) orelse return errno.EFAULT;

    const handle = runtime.boot().ipc.create() catch |err| switch (err) {
        pipe.PipeError.TooManyPipes => return errno.EMFILE,
        else => return errno.EIO,
    };

    const proc = fdtab.currentProcess() catch {
        runtime.boot().ipc.closeRead(handle);
        runtime.boot().ipc.closeWrite(handle);
        return errno.EPERM;
    };

    const read_fd = fdtab.alloc(proc) catch {
        runtime.boot().ipc.closeRead(handle);
        runtime.boot().ipc.closeWrite(handle);
        return errno.EMFILE;
    };
    proc.fds.fds[read_fd] = .{ .pipe_fd = .{ .handle = handle, .is_read = true } };

    const write_fd = fdtab.alloc(proc) catch {
        proc.fds.fds[read_fd] = .none;
        runtime.boot().ipc.closeRead(handle);
        runtime.boot().ipc.closeWrite(handle);
        return errno.EMFILE;
    };
    proc.fds.fds[write_fd] = .{ .pipe_fd = .{ .handle = handle, .is_read = false } };

    out.* = .{ @intCast(read_fd), @intCast(write_fd) };
    return 0;
}

fn sysDup(old_fd: u64) i64 {
    if (old_fd >= process.max_fds) return errno.EBADF;
    const proc = fdtab.currentProcess() catch return errno.EPERM;
    _ = fdtab.slot(proc, old_fd) catch return errno.EBADF;

    const old_entry = proc.fds.fds[@intCast(old_fd)];
    const new_fd = fdtab.alloc(proc) catch return errno.EMFILE;
    if (!fd_retain.retain(old_entry)) return errno.EBADF;
    proc.fds.fds[new_fd] = old_entry;

    return @intCast(new_fd);
}

fn sysDup2(old_fd: u64, new_fd: u64) i64 {
    if (old_fd >= process.max_fds or new_fd >= process.max_fds) return errno.EBADF;
    if (old_fd == new_fd) return @intCast(new_fd);

    const proc = fdtab.currentProcess() catch return errno.EPERM;
    const old_entry = fdtab.slot(proc, old_fd) catch return errno.EBADF;

    // If new_fd is open, close it first
    if (proc.fds.fds[@intCast(new_fd)] != .none) {
        _ = fd_ops.close(&proc.fds.fds[@intCast(new_fd)]);
    }

    if (!fd_retain.retain(old_entry.*)) return errno.EBADF;
    proc.fds.fds[@intCast(new_fd)] = old_entry.*;

    return @intCast(new_fd);
}

fn sysExit(status: u64) i64 {
    if (process.currentProcess() != null) {
        process.terminateCurrent(abi_signal.waitStatusForExit(@truncate(status)));
    }
    thread.exit();
}

/// Linux reboot(2): magic1=0xfee1dead, magic2=672274793, cmd=POWER_OFF(0x4321fedc).
fn sysReboot(magic1: u64, magic2: u64, cmd: u64, _: u64) i64 {
    const linux_reboot_magic1: u64 = 0xfee1dead;
    const linux_reboot_magic2: u64 = 672274793;
    const linux_reboot_cmd_power_off: u64 = 0x4321fedc;
    if (magic1 != linux_reboot_magic1 or magic2 != linux_reboot_magic2) return errno.EINVAL;
    if (cmd != linux_reboot_cmd_power_off) return errno.EINVAL;
    const power = @import("../acpi/power.zig");
    power.powerOff();
}

fn sysRtSigaction(signum: u64, act_ptr: u64, oldact_ptr: u64, sigsetsize: u64) i64 {
    if (sigsetsize != abi_signal.sigset_wordsize) return errno.EINVAL;
    const proc = process.currentProcess() orelse return errno.EPERM;
    const sig = @as(u32, @intCast(signum));
    if (!abi_signal.isValid(sig)) return errno.EINVAL;

    const act = if (act_ptr != 0) user.value(abi_signal.Sigaction, act_ptr) else null;
    const old_action = signal.sigaction(proc, sig, act) catch return errno.EINVAL;

    if (oldact_ptr != 0) {
        const old = abi_signal.Sigaction{
            .sa_handler = signal.actionToHandler(old_action),
            .sa_flags = 0,
            .sa_restorer = 0,
            .sa_mask = 0,
        };
        copy_out.copyOut(oldact_ptr, std.mem.asBytes(&old)) catch return errno.EFAULT;
    }
    return 0;
}

fn sysRtSigprocmask(how: u64, set_ptr: u64, oldset_ptr: u64, sigsetsize: u64) i64 {
    if (sigsetsize != abi_signal.sigset_wordsize) return errno.EINVAL;
    const proc = process.currentProcess() orelse return errno.EPERM;
    const set: u64 = if (set_ptr != 0)
        user.value(u64, set_ptr) orelse return errno.EFAULT
    else
        0;
    const old = signal.sigprocmask(proc, @intCast(how), set);
    if (old < 0) return old;
    if (oldset_ptr != 0) {
        const old_u64: u64 = @intCast(old);
        copy_out.copyOut(oldset_ptr, std.mem.asBytes(&old_u64)) catch return errno.EFAULT;
    }
    return 0;
}

fn sysKill(pid: u64, sig: u64) i64 {
    if (pid == 0 or @as(i64, @bitCast(pid)) < 0) return errno.EINVAL;
    const signum = @as(u32, @intCast(sig));
    if (!abi_signal.isValid(signum)) return errno.EINVAL;
    if (!signal.send(@intCast(pid), signum)) return errno.ESRCH;
    return 0;
}
