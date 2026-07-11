/// Switch two contexts with the x86_64 callee-saved-register ABI. Context
/// layout validation remains with the owning scheduler type.
extern fn x86_switch_context(from: *anyopaque, to: *const anyopaque) callconv(.{ .x86_64_sysv = .{} }) void;

comptime {
    asm (
        \\.global x86_switch_context
        \\.type x86_switch_context, @function
        \\x86_switch_context:
        \\  mov %rbx, 0(%rdi)
        \\  mov %rbp, 8(%rdi)
        \\  mov %r12, 16(%rdi)
        \\  mov %r13, 24(%rdi)
        \\  mov %r14, 32(%rdi)
        \\  mov %r15, 40(%rdi)
        \\  mov %rsp, 48(%rdi)
        \\  mov (%rsp), %rax
        \\  mov %rax, 56(%rdi)
        \\  mov 0(%rsi), %rbx
        \\  mov 8(%rsi), %rbp
        \\  mov 16(%rsi), %r12
        \\  mov 24(%rsi), %r13
        \\  mov 32(%rsi), %r14
        \\  mov 40(%rsi), %r15
        \\  mov 48(%rsi), %rsp
        \\  ret
    );
}

pub fn switchContext(from: *anyopaque, to: *const anyopaque) void { x86_switch_context(from, to); }
