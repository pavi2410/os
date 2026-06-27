/// Freestanding entry point linked into every user program via `libc`.
export fn _start() callconv(.naked) noreturn {
    asm volatile (
        \\ call main
        \\ mov $60, %%rax
        \\ xor %%rdi, %%rdi
        \\ syscall
        ::: .{ .memory = true });
    unreachable;
}
