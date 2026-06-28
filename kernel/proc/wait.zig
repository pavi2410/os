const cpu = @import("../arch/x86_64/cpu.zig");
const process = @import("process.zig");
const scheduler = @import("scheduler.zig");

const WNOHANG: u32 = 1;
const ECHILD: i64 = -10;

pub fn wait4(parent: *process.Process, pid: i64, status_ptr: u64, options: u32) i64 {
    while (true) {
        if (process.reapZombieAny(parent.id, pid)) |zombie| {
            if (status_ptr != 0) {
                parent.address_space.activate();
                const wstatus: u32 = zombie.status << 8;
                const out: *u32 = @ptrFromInt(status_ptr);
                out.* = wstatus;
            }
            return @intCast(zombie.pid);
        }

        if (options & WNOHANG != 0) return 0;

        if (!process.hasChild(parent.id, pid)) return ECHILD;

        cpu.sti();
        scheduler.yield();
        cpu.cli();
    }
}
