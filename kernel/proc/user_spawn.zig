const cpu = @import("../arch/x86_64/cpu.zig");
const gdt = @import("../arch/x86_64/gdt.zig");
const process = @import("process.zig");
const programs = @import("programs.zig");
const scheduler = @import("scheduler.zig");
const thread = @import("thread.zig");
const user_entry = @import("user_entry.zig");
const user_loader = @import("../mm/user_loader.zig");

var spawn_status: i64 = 0;
var spawn_done = false;
var waiting_thread: ?*thread.Thread = null;

pub fn isWaiting() bool {
    return !spawn_done;
}

var pending_proc: ?*process.Process = null;
var pending_image: ?user_loader.LoadedImage = null;

pub fn spawn(path: []const u8) i64 {
    const parent = process.currentProcess();
    const image = programs.get(path) orelse return -2;

    const child = process.create() catch return -12;
    const loaded = process.loadElf(child, image) catch return -12;

    spawn_done = false;
    waiting_thread = thread.currentThread();
    pending_proc = child;
    pending_image = loaded;

    scheduler.spawn(userProcessEntry, "user-child") catch return -12;

    while (!spawn_done) {
        cpu.sti();
        scheduler.yield();
        cpu.cli();
    }

    waiting_thread = null;
    // The child's exit switched CR3 to the kernel space; restore the parent's.
    if (parent) |p| {
        process.setCurrent(p);
        p.address_space.activate();
    }
    return spawn_status;
}

pub fn onChildExit(status: u32) void {
    if (spawn_done) return;
    spawn_status = @intCast(status);
    spawn_done = true;
}

fn userProcessEntry() callconv(.{ .x86_64_sysv = .{} }) noreturn {
    const proc = pending_proc orelse thread.exit();
    const image = pending_image orelse thread.exit();
    pending_proc = null;
    pending_image = null;

    const self = thread.currentThread() orelse thread.exit();
    const kstack = (@intFromPtr(self.stack) + self.stack_size) & ~@as(u64, 15);
    process.enterUser(proc, image, kstack);
}
