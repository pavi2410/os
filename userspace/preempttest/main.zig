const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;
pub const panic = @import("ulib").panic.handler;

const ulib = @import("ulib");
const tap = @import("preempttest_tap");

/// Pure user-mode busy loop — never yields or makes syscalls.
fn busyForever() noreturn {
    while (true) {
        asm volatile ("" ::: .{ .memory = true });
    }
}

export fn main(_argc: usize, _argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) u8 {
    _ = _argc;
    _ = _argv;

    tap.Harness.version();
    tap.Harness.plan(2);
    testParentProgressUnderBusyChild();
    testTwoBusyChildrenParentProgress();
    return tap.Harness.finish();
}

fn testParentProgressUnderBusyChild() void {
    const child = ulib.process.fork();
    if (child < 0) {
        tap.Harness.notOk("parent progress under busy child", "fork failed");
        return;
    }
    if (child == 0) busyForever();

    const start = ulib.time.monotonicUs();
    var iters: u64 = 0;
    while (ulib.time.elapsedUs(start, ulib.time.monotonicUs()) < 300_000) {
        iters += 1;
        if (iters % 10_000 == 0) {
            _ = ulib.time.monotonicUs();
        }
    }

    _ = ulib.signal.kill(child, ulib.signal.SIGKILL);
    var status: u32 = 0;
    _ = ulib.process.wait(child, &status, 0);

    tap.Harness.check("parent progress under busy child", iters > 1_000);
}

fn testTwoBusyChildrenParentProgress() void {
    const a = ulib.process.fork();
    if (a < 0) {
        tap.Harness.notOk("two busy children parent progress", "fork A failed");
        return;
    }
    if (a == 0) busyForever();

    const b = ulib.process.fork();
    if (b < 0) {
        _ = ulib.signal.kill(a, ulib.signal.SIGKILL);
        var st: u32 = 0;
        _ = ulib.process.wait(a, &st, 0);
        tap.Harness.notOk("two busy children parent progress", "fork B failed");
        return;
    }
    if (b == 0) busyForever();

    const start = ulib.time.monotonicUs();
    var iters: u64 = 0;
    while (ulib.time.elapsedUs(start, ulib.time.monotonicUs()) < 400_000) {
        iters += 1;
        if (iters % 10_000 == 0) {
            _ = ulib.time.monotonicUs();
        }
    }

    _ = ulib.signal.kill(a, ulib.signal.SIGKILL);
    _ = ulib.signal.kill(b, ulib.signal.SIGKILL);
    var status: u32 = 0;
    _ = ulib.process.wait(a, &status, 0);
    _ = ulib.process.wait(b, &status, 0);

    tap.Harness.check("two busy children parent progress", iters > 1_000);
}
