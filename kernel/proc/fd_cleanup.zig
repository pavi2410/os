const fd_table = @import("fd_table.zig");
const pipe = @import("../ipc/pipe.zig");
const socket = @import("../net/socket.zig");
const vfs = @import("../fs/vfs.zig");
const runtime = @import("../runtime.zig");

/// Release all resources referenced by a process descriptor table.
pub fn closeAll(table: *fd_table.FdTable) void {
    for (&table.fds) |*entry| {
        switch (entry.*) {
            .file => |handle| runtime.boot().vfs.close(handle),
            .socket => |handle| socket.close(handle),
            .pipe_fd => |pfd| {
                if (pfd.is_read) runtime.boot().ipc.closeRead(pfd.handle) else runtime.boot().ipc.closeWrite(pfd.handle);
            },
            .none, .console, .device => {},
        }
        entry.* = .none;
    }
}
