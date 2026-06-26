const cpu = @import("../arch/x86_64/cpu.zig");
const process = @import("process.zig");
const programs = @import("programs.zig");
const scheduler = @import("scheduler.zig");
const serial = @import("../arch/x86_64/serial.zig");
const thread = @import("thread.zig");
const user_loader = @import("../mm/user_loader.zig");

var init_proc: ?*process.Process = null;
var init_image: ?user_loader.LoadedImage = null;

pub fn launch() void {
    const image = programs.get("/shell") orelse {
        serial.writeString("shell image missing (build user programs first)\r\n");
        return;
    };

    init_proc = process.create() catch {
        serial.writeString("init process create failed\r\n");
        return;
    };
    init_image = process.loadElf(init_proc.?, image) catch {
        serial.writeString("shell load failed\r\n");
        return;
    };

    scheduler.spawn(initShellEntry, "init-shell") catch {
        serial.writeString("init-shell spawn failed\r\n");
        return;
    };

    serial.writeString("Starting shell\r\n");
}

fn initShellEntry() callconv(.{ .x86_64_sysv = .{} }) noreturn {
    const proc = init_proc orelse thread.exit();
    const image = init_image orelse thread.exit();
    const self = thread.currentThread() orelse thread.exit();
    const kstack = (@intFromPtr(self.stack) + self.stack_size) & ~@as(u64, 15);
    process.enterUser(proc, image, kstack);
}
