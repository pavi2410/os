const fd_table = @import("fd_table.zig");
const pipe = @import("../ipc/pipe.zig");
const socket = @import("../net/socket.zig");
const vfs = @import("../fs/vfs.zig");

pub fn retain(entry: fd_table.Fd) bool {
    switch (entry) {
        .file => |handle| vfs.retain(handle) catch return false,
        .socket => |handle| if (!socket.retain(handle)) return false,
        .pipe_fd => |pfd| pipe.dupRef(pfd.handle, pfd.is_read),
        .none, .console, .device => {},
    }
    return true;
}

pub fn retainAll(table: *const fd_table.FdTable) bool {
    for (table.fds) |entry| {
        if (!retain(entry)) return false;
    }
    return true;
}
