const process = @import("proc/process.zig");
const scheduler = @import("proc/scheduler.zig");
const pipe = @import("ipc/pipe.zig");
const socket_table = @import("net/socket/table.zig");
const vfs = @import("fs/vfs.zig");
const thread = @import("proc/thread.zig");

/// Composition root for services that have completed their explicit-state
/// extraction. Additional resource tables migrate here incrementally.
pub const Runtime = struct {
    processes: process.ProcessTable = .{},
    scheduler: scheduler.SchedulerState = .{},
    pipes: pipe.PipeTable = .{},
    sockets: socket_table.SocketTable = .{},
    vfs_handles: vfs.HandleTable = .{},
    threads: thread.Runtime = .{},

    pub fn install(self: *Runtime) void {
        process.installTable(&self.processes);
        scheduler.installState(&self.scheduler);
        pipe.installTable(&self.pipes);
        socket_table.installTable(&self.sockets);
        vfs.installHandleTable(&self.vfs_handles);
        thread.installRuntime(&self.threads);
    }
};
