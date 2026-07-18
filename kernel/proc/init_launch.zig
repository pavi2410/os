const process = @import("process.zig");
const programs = @import("programs.zig");
const scheduler = @import("scheduler.zig");
const hal = @import("../hal.zig");
const heap = @import("../mm/heap.zig");
const thread = @import("thread.zig");
const user_loader = @import("../mm/user_loader.zig");

var init_proc: ?*process.Process = null;
var init_image: ?user_loader.LoadedImage = null;

pub fn launch() void {
    const image_buf = programs.load(programs.initPath()) catch |err| {
        hal.console.println("init not found on disk ({s}): {s} (run: mise run disk)", .{
            programs.initPath(),
            @errorName(err),
        });
        return;
    };
    defer heap.kfree(image_buf.ptr) catch {};

    init_proc = process.create() catch {
        hal.console.println("init process create failed", .{});
        return;
    };
    init_image = process.loadElf(init_proc.?, image_buf, &.{programs.initPath()}, &.{}) catch {
        hal.console.println("init load failed", .{});
        return;
    };

    scheduler.spawn(initEntry, "init") catch {
        hal.console.println("init spawn failed", .{});
        return;
    };

    hal.console.println("Starting init", .{});
}

fn initEntry() callconv(.{ .x86_64_sysv = .{} }) noreturn {
    const proc = init_proc orelse thread.exit();
    const image = init_image orelse thread.exit();
    const self = thread.currentThread() orelse thread.exit();
    const kstack = (@intFromPtr(self.stack) + self.stack_size) & ~@as(u64, 15);
    process.enterUser(proc, image, kstack);
}
