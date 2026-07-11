const process = @import("proc/process.zig");
const scheduler = @import("proc/scheduler.zig");
const pipe = @import("ipc/pipe.zig");
const socket_table = @import("net/socket/table.zig");
const vfs = @import("fs/vfs.zig");
const thread = @import("proc/thread.zig");

/// Composition root for services that have completed their explicit-state
/// extraction. Additional resource tables migrate here incrementally.
pub const Runtime = struct {
    processes: process.ProcessManager = .{},
    scheduler: scheduler.Scheduler = .{},
    pipes: pipe.PipeTable = .{},
    network: socket_table.Network = .{},
    vfs: vfs.Vfs = .{},
    threads: thread.Runtime = .{},

    pub fn install(self: *Runtime) void {
        process.install(&self.processes);
        scheduler.install(&self.scheduler);
        pipe.installTable(&self.pipes);
        socket_table.install(&self.network);
        vfs.install(&self.vfs);
        thread.installRuntime(&self.threads);
    }
};
