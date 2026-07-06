const process = @import("process.zig");
const programs = @import("programs.zig");
const scheduler = @import("scheduler.zig");
const hal = @import("../hal.zig");
const thread = @import("thread.zig");
const user_loader = @import("../mm/user_loader.zig");

var init_proc: ?*process.Process = null;
var init_image: ?user_loader.LoadedImage = null;

pub fn launch() void {
    const image_buf = programs.load(programs.initShellPath()) catch |err| {
        hal.console.printf("shell not found on disk ({s}): {s} (run: mise run disk)\r\n", .{
            programs.initShellPath(),
            @errorName(err),
        });
        return;
    };
    defer programs.free(image_buf);

    init_proc = process.create() catch {
        hal.console.writeString("init process create failed\r\n");
        return;
    };
    init_image = process.loadElf(init_proc.?, image_buf, &.{programs.initShellPath()}) catch {
        hal.console.writeString("shell load failed\r\n");
        return;
    };

    scheduler.spawn(initShellEntry, "init-shell") catch {
        hal.console.writeString("init-shell spawn failed\r\n");
        return;
    };

    hal.console.writeString("Starting shell\r\n");
}

fn initShellEntry() callconv(.{ .x86_64_sysv = .{} }) noreturn {
    const proc = init_proc orelse thread.exit();
    const image = init_image orelse thread.exit();
    const self = thread.currentThread() orelse thread.exit();
    const kstack = (@intFromPtr(self.stack) + self.stack_size) & ~@as(u64, 15);
    process.enterUser(proc, image, kstack);
}
