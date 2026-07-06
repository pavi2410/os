const process = @import("../proc/process.zig");
const socket = @import("../net/socket.zig");
const tty = @import("../drivers/tty.zig");
const vfs = @import("../fs/vfs.zig");
const errno = @import("errno.zig");

pub fn read(fd: u64, slot: *process.Fd, buf: []u8) i64 {
    return switch (slot.kind) {
        .console => {
            if (fd != 0) return errno.EBADF;
            const read_len = tty.get().read(buf) catch |err| switch (err) {
                tty.TtyError.WouldBlock => return errno.EINTR,
            };
            return @intCast(read_len);
        },
        .file => {
            const n = vfs.read(slot.vfs_handle, buf) catch |err| return errno.fromVfs(err);
            return @intCast(n);
        },
        .socket, .none => errno.EBADF,
    };
}

pub fn write(fd: u64, slot: *process.Fd, buf: []const u8) i64 {
    return switch (slot.kind) {
        .console => {
            if (fd != 1 and fd != 2) return errno.EBADF;
            return @intCast(tty.get().write(buf));
        },
        .file => {
            const n = vfs.write(slot.vfs_handle, buf) catch |err| return errno.fromVfs(err);
            return @intCast(n);
        },
        .socket, .none => errno.EBADF,
    };
}

pub fn close(slot: *process.Fd) i64 {
    return switch (slot.kind) {
        .file => {
            vfs.close(slot.vfs_handle);
            slot.* = .{};
            return 0;
        },
        .socket => {
            socket.close(slot.socket_handle);
            slot.* = .{};
            return 0;
        },
        .console => {
            slot.* = .{};
            return 0;
        },
        .none => errno.EBADF,
    };
}

pub fn lseek(slot: *process.Fd, offset: i64, whence: u32) i64 {
    if (slot.kind != .file) return errno.EBADF;
    const pos = vfs.lseek(slot.vfs_handle, offset, @enumFromInt(whence)) catch |err| return errno.fromVfs(err);
    return @bitCast(@as(i64, @intCast(pos)));
}

pub fn getdents64(slot: *process.Fd, buf: []u8) i64 {
    if (slot.kind != .file) return errno.EBADF;
    const n = vfs.getdents64(slot.vfs_handle, buf) catch |err| return errno.fromVfs(err);
    return @intCast(n);
}
