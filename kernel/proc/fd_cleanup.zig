const fd_table = @import("fd_table.zig");
const pipe = @import("../ipc/pipe.zig");
const socket = @import("../net/socket.zig");
const vfs = @import("../fs/vfs.zig");

/// Release all resources referenced by a process descriptor table.
pub fn closeAll(table: *fd_table.FdTable) void {
    for (&table.fds) |*entry| {
        switch (entry.*) {
            .file => |handle| vfs.close(handle),
            .socket => |handle| socket.close(handle),
            .pipe_fd => |pfd| {
                if (pfd.is_read) pipe.closeRead(pfd.handle) else pipe.closeWrite(pfd.handle);
            },
            .none, .console, .device => {},
        }
        entry.* = .none;
    }
}
