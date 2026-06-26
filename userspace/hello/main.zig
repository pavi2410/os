const libc = @import("libc");

export fn _start() callconv(.naked) noreturn {
    asm volatile (
        \\ call main
        \\ mov $60, %%rax
        \\ xor %%rdi, %%rdi
        \\ syscall
        ::: .{ .memory = true });
    unreachable;
}

export fn main() callconv(.{ .x86_64_sysv = .{} }) void {
    const msg = "Hello from userspace!\n";
    _ = libc.syscall.write(1, msg.ptr, msg.len);
    libc.syscall.exit(0);
}
