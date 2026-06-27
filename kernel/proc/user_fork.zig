/// User register snapshot at the point of `fork`, used to resume after `sysret`.
pub const ForkUserContext = struct {
    rbx: u64,
    rbp: u64,
    r12: u64,
    r13: u64,
    r14: u64,
    r15: u64,
    rdi: u64,
    rsi: u64,
    rdx: u64,
    r10: u64,
    r8: u64,
    r9: u64,
    user_rip: u64,
    user_rflags: u64,
    user_rsp: u64,

    pub fn captureFromSyscall(
        arg0: u64,
        arg1: u64,
        arg2: u64,
        arg3: u64,
        arg4: u64,
        arg5: u64,
        user_rip: u64,
        user_rflags: u64,
        user_rsp: u64,
    ) ForkUserContext {
        var rbx: u64 = 0;
        var rbp: u64 = 0;
        var r12: u64 = 0;
        var r13: u64 = 0;
        var r14: u64 = 0;
        var r15: u64 = 0;

        asm volatile (
            \\ mov %%rbx, %[rbx]
            \\ mov %%rbp, %[rbp]
            \\ mov %%r12, %[r12]
            \\ mov %%r13, %[r13]
            \\ mov %%r14, %[r14]
            \\ mov %%r15, %[r15]
            : [rbx] "=r" (rbx),
              [rbp] "=r" (rbp),
              [r12] "=r" (r12),
              [r13] "=r" (r13),
              [r14] "=r" (r14),
              [r15] "=r" (r15),
            :
            : .{ .memory = true });

        return .{
            .rbx = rbx,
            .rbp = rbp,
            .r12 = r12,
            .r13 = r13,
            .r14 = r14,
            .r15 = r15,
            .rdi = arg0,
            .rsi = arg1,
            .rdx = arg2,
            .r10 = arg3,
            .r8 = arg4,
            .r9 = arg5,
            .user_rip = user_rip,
            .user_rflags = user_rflags,
            .user_rsp = user_rsp,
        };
    }
};

extern fn forkReturnToUser(ctx: *const ForkUserContext, ret: u64) callconv(.{ .x86_64_sysv = .{} }) noreturn;

comptime {
    if (@offsetOf(ForkUserContext, "rbx") != 0) @compileError("ForkUserContext layout mismatch");
    if (@offsetOf(ForkUserContext, "rdi") != 48) @compileError("ForkUserContext layout mismatch");
    if (@offsetOf(ForkUserContext, "user_rip") != 96) @compileError("ForkUserContext layout mismatch");
    if (@offsetOf(ForkUserContext, "user_rsp") != 112) @compileError("ForkUserContext layout mismatch");
    if (@sizeOf(ForkUserContext) != 120) @compileError("ForkUserContext must be 120 bytes");

    asm (
        \\ .global forkReturnToUser
        \\ .type forkReturnToUser, @function
        \\ forkReturnToUser:
        \\   mov %rdi, %r8
        \\   mov %rsi, %rax
        \\   mov (%r8), %rbx
        \\   mov 0x8(%r8), %rbp
        \\   mov 0x10(%r8), %r12
        \\   mov 0x18(%r8), %r13
        \\   mov 0x20(%r8), %r14
        \\   mov 0x28(%r8), %r15
        \\   mov 0x30(%r8), %rdi
        \\   mov 0x38(%r8), %rsi
        \\   mov 0x40(%r8), %rdx
        \\   mov 0x48(%r8), %r10
        \\   mov 0x58(%r8), %r9
        \\   mov 0x60(%r8), %rcx
        \\   mov 0x68(%r8), %r11
        \\   mov 0x70(%r8), %rsp
        \\   mov 0x50(%r8), %r8
        \\   sysretq
    );
}

/// Return to ring 3 after `fork` with `ret` in `%rax` (0 in the child).
pub fn returnToUser(ctx: ForkUserContext, ret: u64) noreturn {
    var copy = ctx;
    forkReturnToUser(&copy, ret);
}
