pub const max_fds = 32;

const devfs = @import("../fs/devfs.zig");
const pipe = @import("../ipc/pipe.zig");

pub const DeviceFd = struct {
    kind: devfs.Device,
    readable: bool,
    writable: bool,
};

pub const Fd = union(enum) {
    none,
    console,
    file: u32,
    device: DeviceFd,
    socket: u32,
    pipe_fd: pipe.PipeFd,
};

/// Per-process file descriptor table.
pub const FdTable = struct {
    fds: [max_fds]Fd,

    pub fn init() FdTable {
        var table = FdTable{
            .fds = undefined,
        };
        for (&table.fds) |*fd| {
            fd.* = .none;
        }
        table.fds[0] = .console;
        table.fds[1] = .console;
        table.fds[2] = .console;
        return table;
    }

    pub fn allocFd(self: *FdTable) ?usize {
        var i: usize = 3;
        while (i < max_fds) : (i += 1) {
            if (self.fds[i] == .none) return i;
        }
        return null;
    }

    pub fn isOpen(self: *const FdTable, fd: usize) bool {
        if (fd >= max_fds) return false;
        return self.fds[fd] != .none;
    }

    /// Retain resources copied into a child table during fork.
    pub fn retainAll(self: *const FdTable) void {
        for (self.fds) |entry| {
            switch (entry) {
                .pipe_fd => |pfd| pipe.dupRef(pfd.handle, pfd.is_read),
                else => {},
            }
        }
    }

};
