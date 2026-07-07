const process = @import("../proc/process.zig");
const socket = @import("../net/socket.zig");
const tty = @import("../drivers/tty.zig");
const vfs = @import("../fs/vfs.zig");
const errno = @import("errno.zig");

pub fn read(fd: u64, slot: *process.Fd, buf: []u8) i64 {
    return switch (slot.*) {
        .console => {
            if (fd != 0) return errno.EBADF;
            const read_len = tty.get().read(buf) catch |err| switch (err) {
                tty.TtyError.WouldBlock => return errno.EINTR,
            };
            return @intCast(read_len);
        },
        .file => |handle| {
            const n = vfs.read(handle, buf) catch |err| return errno.fromVfs(err);
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
        .file => |handle| {
            const n = vfs.write(handle, buf) catch |err| return errno.fromVfs(err);
            return @intCast(n);
        },
        .socket, .none => errno.EBADF,
    };
}

pub fn close(slot: *process.Fd) i64 {
    return switch (slot.*) {
        .file => |handle| {
            vfs.close(handle);
            slot.* = .none;
            return 0;
        },
        .socket => |handle| {
            socket.close(handle);
            slot.* = .none;
            return 0;
        },
        .console => {
            slot.* = .none;
            return 0;
        },
        .none => errno.EBADF,
    };
}

pub fn lseek(slot: *process.Fd, offset: i64, whence: u32) i64 {
    return switch (slot.*) {
        .file => |handle| {
            const pos = vfs.lseek(handle, offset, @enumFromInt(whence)) catch |err| return errno.fromVfs(err);
            return @bitCast(@as(i64, @intCast(pos)));
        },
        else => errno.EBADF,
    };
}

pub fn getdents64(slot: *process.Fd, buf: []u8) i64 {
    return switch (slot.*) {
        .file => |handle| {
            const n = vfs.getdents64(handle, buf) catch |err| return errno.fromVfs(err);
            return @intCast(n);
        },
        else => errno.EBADF,
    };
}
