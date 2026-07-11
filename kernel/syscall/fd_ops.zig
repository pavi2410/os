const process = @import("../proc/process.zig");
const devfs = @import("../fs/devfs.zig");
const socket = @import("../net/socket.zig");
const tty = @import("../drivers/tty.zig");
const vfs = @import("../fs/vfs.zig");
const pipe = @import("../ipc/pipe.zig");
const runtime = @import("../runtime.zig");
const errno = @import("errno.zig");

pub fn read(fd: u64, slot: *process.Fd, buf: []u8) i64 {
    return switch (slot.*) {
        .console => {
            if (fd != 0) return errno.EBADF;
            const read_len = tty.get().read(buf) catch |err| switch (err) {
                tty.TtyError.WouldBlock => return errno.EINTR,
            };
            if (process.currentProcess()) |proc| {
                tty.get().markConsoleReader(proc.id);
            }
            return @intCast(read_len);
        },
        .device => |dev_fd| {
            if (!dev_fd.readable) return errno.EBADF;
            if (dev_fd.kind == .tty_dev) {
                const read_len = tty.get().read(buf) catch |err| switch (err) {
                    tty.TtyError.WouldBlock => return errno.EINTR,
                };
                if (process.currentProcess()) |proc| {
                    tty.get().markConsoleReader(proc.id);
                }
                return @intCast(read_len);
            }
            return @intCast(devfs.readDevice(dev_fd.kind, buf));
        },
        .file => |handle| {
            const n = runtime.boot().vfs.read(handle, buf) catch |err| return errno.fromVfs(err);
            return @intCast(n);
        },
        .pipe_fd => |pfd| {
            const n = runtime.boot().ipc.read(pfd.handle, buf) catch |err| {
                return switch (err) {
                    pipe.PipeError.BrokenPipe => 0,
                    pipe.PipeError.WouldBlock => errno.EAGAIN,
                    pipe.PipeError.TooManyPipes => errno.EIO,
                };
            };
            return @intCast(n);
        },
        .socket, .none => errno.EBADF,
    };
}

pub fn write(fd: u64, slot: *process.Fd, buf: []const u8) i64 {
    return switch (slot.*) {
        .console => {
            if (fd != 1 and fd != 2) return errno.EBADF;
            return @intCast(tty.get().write(buf));
        },
        .device => |dev_fd| {
            if (!dev_fd.writable) return errno.EBADF;
            if (dev_fd.kind == .tty_dev) {
                return @intCast(tty.get().write(buf));
            }
            return @intCast(devfs.writeDevice(dev_fd.kind, buf));
        },
        .file => |handle| {
            const n = runtime.boot().vfs.write(handle, buf) catch |err| return errno.fromVfs(err);
            return @intCast(n);
        },
        .pipe_fd => |pfd| {
            if (!pfd.is_read) {
                const n = runtime.boot().ipc.write(pfd.handle, buf) catch |err| {
                    return switch (err) {
                        pipe.PipeError.BrokenPipe => errno.EPIPE,
                        pipe.PipeError.WouldBlock => errno.EAGAIN,
                        pipe.PipeError.TooManyPipes => errno.EIO,
                    };
                };
                return @intCast(n);
            }
            return errno.EBADF;
        },
        .socket, .none => errno.EBADF,
    };
}

pub fn close(slot: *process.Fd) i64 {
    return switch (slot.*) {
        .file => |handle| {
            runtime.boot().vfs.close(handle);
            slot.* = .none;
            return 0;
        },
        .socket => |handle| {
            socket.close(&runtime.boot().network, handle);
            slot.* = .none;
            return 0;
        },
        .pipe_fd => |pfd| {
            if (pfd.is_read) {
                runtime.boot().ipc.closeRead(pfd.handle);
            } else {
                runtime.boot().ipc.closeWrite(pfd.handle);
            }
            slot.* = .none;
            return 0;
        },
        .console, .device => {
            slot.* = .none;
            return 0;
        },
        .none => errno.EBADF,
    };
}

pub fn lseek(slot: *process.Fd, offset: i64, whence: u32) i64 {
    return switch (slot.*) {
        .file => |handle| {
            const pos = runtime.boot().vfs.lseek(handle, offset, @enumFromInt(whence)) catch |err| return errno.fromVfs(err);
            return @bitCast(@as(i64, @intCast(pos)));
        },
        else => errno.EBADF,
    };
}

pub fn getdents64(slot: *process.Fd, buf: []u8) i64 {
    return switch (slot.*) {
        .file => |handle| {
            const n = runtime.boot().vfs.getdents64(handle, buf) catch |err| return errno.fromVfs(err);
            return @intCast(n);
        },
        else => errno.EBADF,
    };
}
