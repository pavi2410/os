const gdt = @import("gdt.zig");
const paging = @import("paging.zig");

/// Saved user register state at a syscall boundary. This x86_64 ABI layout is
/// consumed only by the architecture return stub below.
pub const ForkContext = struct {
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

    pub fn captureFromSyscallFrame(frame: anytype) ForkContext {
        return .{
            .rbx = frame.rbx,
            .rbp = frame.rbp,
            .r12 = frame.r12,
            .r13 = frame.r13,
            .r14 = frame.r14,
            .r15 = frame.r15,
            .rdi = frame.arg0,
            .rsi = frame.arg1,
            .rdx = frame.arg2,
            .r10 = frame.arg3,
            .r8 = frame.arg4,
            .r9 = frame.arg5,
            .user_rip = frame.user_rip,
            .user_rflags = frame.user_rflags,
            .user_rsp = frame.user_rsp,
        };
    }
};

comptime {
    if (@offsetOf(ForkContext, "rbx") != 0) @compileError("ForkContext layout mismatch");
    if (@offsetOf(ForkContext, "rdi") != 48) @compileError("ForkContext layout mismatch");
    if (@offsetOf(ForkContext, "user_rip") != 96) @compileError("ForkContext layout mismatch");
    if (@offsetOf(ForkContext, "user_rsp") != 112) @compileError("ForkContext layout mismatch");
    if (@sizeOf(ForkContext) != 120) @compileError("ForkContext must be 120 bytes");

    asm (
        \\ .global x86_fork_return_to_user
        \\ .type x86_fork_return_to_user, @function
        \\ x86_fork_return_to_user:
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

extern fn x86_fork_return_to_user(ctx: *const ForkContext, ret: u64) callconv(.{ .x86_64_sysv = .{} }) noreturn;

/// Return to ring 3 after fork with `ret` in rax.
pub fn returnAfterFork(ctx: ForkContext, ret: u64) noreturn {
    var copy = ctx;
    x86_fork_return_to_user(&copy, ret);
}

/// Switch to a user address space and enter ring 3 through an iretq frame.
pub fn enter(entry: u64, user_stack: u64, cr3: u64) noreturn {
    paging.writeCr3(cr3);

    const user_cs: u64 = gdt.user_code_selector | 3;
    const user_ss: u64 = gdt.user_data_selector | 3;
    var sp = user_stack;
    sp -%= 8;
    @as(*u64, @ptrFromInt(sp)).* = user_ss;
    sp -%= 8;
    @as(*u64, @ptrFromInt(sp)).* = user_stack;
    sp -%= 8;
    @as(*u64, @ptrFromInt(sp)).* = 0x202;
    sp -%= 8;
    @as(*u64, @ptrFromInt(sp)).* = user_cs;
    sp -%= 8;
    @as(*u64, @ptrFromInt(sp)).* = entry;
    asm volatile ("mov %[sp], %%rsp; iretq" : : [sp] "r" (sp));
    unreachable;
}
