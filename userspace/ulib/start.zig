/// Freestanding entry point linked into every user program via `ulib`.
export fn _start() callconv(.naked) noreturn {
    asm volatile (
        \\ mov (%%rsp), %%rdi
        \\ lea 8(%%rsp), %%rsi
        \\ call main
        \\ mov %%rax, %%rdi
        \\ mov $60, %%rax
        \\ syscall
        ::: .{ .memory = true });
    unreachable;
}
