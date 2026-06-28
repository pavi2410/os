const freestanding_std = @import("freestanding_std");
const libc = @import("libc");

pub const std_options_debug_io = freestanding_std.std_options_debug_io;
pub const std_options = freestanding_std.std_options;

export fn main() callconv(.{ .x86_64_sysv = .{} }) void {
    const msg = "Hello from userspace!\n";
    _ = libc.syscall.write(1, msg.ptr, msg.len);
    libc.syscall.exit(0);
}
