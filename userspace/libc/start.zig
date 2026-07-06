/// Freestanding entry point linked into every user program via `libc`.
export fn _start() callconv(.naked) noreturn {
    asm volatile (
        \\ mov (%%rsp), %%rdi
        \\ lea 8(%%rsp), %%rsi
        \\ call main
        \\ mov $60, %%rax
        \\ xor %%rdi, %%rdi
        \\ syscall
        ::: .{ .memory = true });
    unreachable;
}
