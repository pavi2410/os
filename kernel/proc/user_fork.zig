const cpu = @import("../arch/x86_64/cpu.zig");
const handlers = @import("../syscall/handlers.zig");

/// User register snapshot at the point of `fork`, used to resume in ring 3.
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

    pub fn captureFromFrame(frame: anytype) ForkUserContext {
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

extern fn syscall_resume_userspace() callconv(.{ .x86_64_sysv = .{} }) noreturn;

/// Return to ring 3 after `fork` with `ret` in `%rax` (0 in the child).
pub fn returnToUser(ctx: ForkUserContext, ret: u64) noreturn {
    var frame: handlers.Frame = .{
        .rbx = ctx.rbx,
        .rbp = ctx.rbp,
        .r12 = ctx.r12,
        .r13 = ctx.r13,
        .r14 = ctx.r14,
        .r15 = ctx.r15,
        .arg0 = ctx.rdi,
        .arg1 = ctx.rsi,
        .arg2 = ctx.rdx,
        .arg3 = ctx.r10,
        .arg4 = ctx.r8,
        .arg5 = ctx.r9,
        .nr = 0,
        .user_rip = ctx.user_rip,
        .user_rflags = ctx.user_rflags | 2,
        .user_rsp = ctx.user_rsp,
    };

    cpu.cli();
    asm volatile (
        \\ mov %[ret], %%rax
        \\ mov %[frame], %%rsp
        \\ jmp syscall_resume_userspace
        :
        : [ret] "r" (ret),
          [frame] "r" (&frame),
    );
    unreachable;
}
