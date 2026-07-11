const process = @import("proc/process.zig");
const scheduler = @import("proc/scheduler.zig");
const pipe = @import("ipc/pipe.zig");

/// Composition root for services that have completed their explicit-state
/// extraction. Additional resource tables migrate here incrementally.
pub const Runtime = struct {
    processes: process.ProcessTable = .{},
    scheduler: scheduler.SchedulerState = .{},
    pipes: pipe.PipeTable = .{},

    pub fn install(self: *Runtime) void {
        process.installTable(&self.processes);
        scheduler.installState(&self.scheduler);
        pipe.installTable(&self.pipes);
    }
};
