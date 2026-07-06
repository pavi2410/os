const freestanding_std = @import("freestanding_std");
const libc = @import("libc");

pub const std_options_debug_io = freestanding_std.std_options_debug_io;
pub const std_options = freestanding_std.std_options;

export fn main(argc: usize, argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) void {
    _ = argc;
    _ = argv;
    const msg = "Hello from userspace!\n";
    libc.io.writeStr(msg);
    libc.process.exit(0);
}
