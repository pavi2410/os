const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;
pub const panic = @import("ulib").panic.handler;

const ulib = @import("ulib");

/// CPU-bound spin for manual experiments.
/// Prefer `/BIN/preempttest` for automated coverage.
export fn main(_argc: usize, _argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) u8 {
    _ = _argc;
    _ = _argv;
    _ = ulib;
    while (true) {
        asm volatile ("" ::: .{ .memory = true });
    }
}
