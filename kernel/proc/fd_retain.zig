const fd_table = @import("fd_table.zig");
const pipe = @import("../ipc/pipe.zig");
const socket = @import("../net/socket.zig");
const vfs = @import("../fs/vfs.zig");
const runtime = @import("../runtime.zig");

pub fn retain(entry: fd_table.Fd) bool {
    switch (entry) {
        .file => |handle| runtime.boot().vfs.retain(handle) catch return false,
        .socket => |handle| if (!socket.retain(handle)) return false,
        .pipe_fd => |pfd| runtime.boot().ipc.dupRef(pfd.handle, pfd.is_read),
        .none, .console, .device => {},
    }
    return true;
}

pub fn retainAll(table: *const fd_table.FdTable) bool {
    var i: usize = 0;
    while (i < table.fds.len) : (i += 1) {
        if (retain(table.fds[i])) continue;
        while (i > 0) {
            i -= 1;
            release(table.fds[i]);
        }
        return false;
    }
    return true;
}

fn release(entry: fd_table.Fd) void {
    switch (entry) {
        .file => |handle| runtime.boot().vfs.close(handle),
        .socket => |handle| socket.close(handle),
        .pipe_fd => |pfd| {
            if (pfd.is_read) runtime.boot().ipc.closeRead(pfd.handle) else runtime.boot().ipc.closeWrite(pfd.handle);
        },
        .none, .console, .device => {},
    }
}
