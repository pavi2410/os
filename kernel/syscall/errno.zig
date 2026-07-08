const socket = @import("../net/socket.zig");
const user_exec = @import("../proc/exec.zig");
const vfs = @import("../fs/vfs.zig");
const filesystem = @import("../fs/filesystem.zig");

pub const EPERM: i64 = -1;
pub const ENOENT: i64 = -2;
pub const EINTR: i64 = -4;
pub const EIO: i64 = -5;
pub const EBADF: i64 = -9;
pub const EAGAIN: i64 = -11;
pub const EACCES: i64 = -13;
pub const EFAULT: i64 = -14;
pub const EEXIST: i64 = -17;
pub const ENOTDIR: i64 = -20;
pub const EINVAL: i64 = -22;
pub const EPIPE: i64 = -32;
pub const ERANGE: i64 = -34;
pub const EISDIR: i64 = -21;
pub const EMFILE: i64 = -24;
pub const ENOSPC: i64 = -28;
pub const ENOSYS: i64 = -38;
pub const ENOTEMPTY: i64 = -39;
pub const ENOTCONN: i64 = -107;
pub const ETIMEDOUT: i64 = -110;

pub fn fromVfs(err: vfs.VfsError) i64 {
    return filesystem.errnoCode(err);
}

pub fn fromSocket(err: socket.SocketError) i64 {
    return switch (err) {
        socket.SocketError.Unsupported => EINVAL,
        socket.SocketError.NotFound, socket.SocketError.NotBound => EBADF,
        socket.SocketError.NotConnected => ENOTCONN,
        socket.SocketError.NotReady, socket.SocketError.IoError => EIO,
        socket.SocketError.Timeout => ETIMEDOUT,
        socket.SocketError.TooManySockets => EMFILE,
    };
}

pub fn fromExec(err: user_exec.ExecError) i64 {
    return switch (err) {
        user_exec.ExecError.NotFound => ENOENT,
        user_exec.ExecError.NotFile => EINVAL,
        user_exec.ExecError.PathTooLong => EINVAL,
        user_exec.ExecError.InvalidElf => ENOENT,
        user_exec.ExecError.OutOfMemory => -12,
        user_exec.ExecError.IoError => EIO,
        user_exec.ExecError.NoProcess => EPERM,
    };
}
