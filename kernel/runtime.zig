const process = @import("proc/process.zig");
const scheduler = @import("proc/scheduler.zig");

/// Composition root for services that have completed their explicit-state
/// extraction. Additional resource tables migrate here incrementally.
pub const Runtime = struct {
    processes: process.ProcessTable = .{},
    scheduler: scheduler.SchedulerState = .{},

    pub fn install(self: *Runtime) void {
        process.installTable(&self.processes);
        scheduler.installState(&self.scheduler);
    }
};
