const cpu = @import("../arch/x86_64/cpu.zig");
const copy_out = @import("../syscall/copy_out.zig");
const errno = @import("../syscall/errno.zig");
const process = @import("process.zig");
const scheduler = @import("scheduler.zig");
const signal = @import("signal.zig");
const std = @import("std");

const WNOHANG: u32 = 1;
const ECHILD: i64 = -10;

pub fn wait4(parent: *process.Process, pid: i64, status_ptr: u64, options: u32) i64 {
    while (true) {
        signal.tryApply(parent);

        if (process.peekZombieAny(parent.id, pid)) |zombie| {
            if (status_ptr != 0) {
                parent.address_space.activate();
                const wstatus: u32 = zombie.status;
                copy_out.copyOut(status_ptr, std.mem.asBytes(&wstatus)) catch return errno.EFAULT;
            }
            // Only reap after a successful status copy (or no status pointer).
            _ = process.reapZombieAny(parent.id, @intCast(zombie.pid));
            return @intCast(zombie.pid);
        }

        if (options & WNOHANG != 0) return 0;

        if (!process.hasChild(parent.id, pid)) return ECHILD;

        cpu.sti();
        scheduler.yield();
        cpu.cli();
    }
}
