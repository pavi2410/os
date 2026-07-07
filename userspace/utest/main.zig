const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;

const tests = @import("tests.zig");

export fn main(_argc: usize, _argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) u8 {
    _ = _argc;
    _ = _argv;
    return tests.runAll();
}
