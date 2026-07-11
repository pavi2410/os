const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;
pub const panic = @import("ulib").panic.handler;

const ulib = @import("ulib");
const tap = @import("cowtest_tap");

var shared_value: u32 = 42;

export fn main(_argc: usize, _argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) u8 {
    _ = _argc;
    _ = _argv;

    tap.Harness.version();
    tap.Harness.plan(2);
    testChildWriteParentUnchanged();
    testBothSidesWrite();
    return tap.Harness.finish();
}

fn testChildWriteParentUnchanged() void {
    shared_value = 42;
    const pid = ulib.process.fork();
    if (pid < 0) {
        tap.Harness.notOk("child write parent unchanged", "fork failed");
        return;
    }
    if (pid == 0) {
        shared_value = 99;
        ulib.process.exit(0);
    }

    var status: u32 = 0;
    _ = ulib.process.wait(pid, &status, 0);
    tap.Harness.check("child write parent unchanged", shared_value == 42);
}

fn testBothSidesWrite() void {
    shared_value = 1;
    const pid = ulib.process.fork();
    if (pid < 0) {
        tap.Harness.notOk("both sides write", "fork failed");
        return;
    }
    if (pid == 0) {
        shared_value = 2;
        ulib.process.exit(0);
    }

    shared_value = 3;
    var status: u32 = 0;
    _ = ulib.process.wait(pid, &status, 0);
    tap.Harness.check("both sides write", shared_value == 3);
}
