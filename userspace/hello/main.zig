const libc = @import("libc");

export fn main() callconv(.{ .x86_64_sysv = .{} }) void {
    const msg = "Hello from userspace!\n";
    _ = libc.syscall.write(1, msg.ptr, msg.len);
    libc.syscall.exit(0);
}
