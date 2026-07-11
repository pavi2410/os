/// Raw Linux-x86_64 syscall register convention used only by the kernel test.
pub const Call = struct {
    nr: u64,
    arg0: u64 = 0,
    arg1: u64 = 0,
    arg2: u64 = 0,
    arg3: u64 = 0,
    arg4: u64 = 0,
    arg5: u64 = 0,
};

/// Issue a syscall from ring 0; the x86 entry stub returns via jmp.
pub fn invoke(args: Call) i64 {
    return asm volatile (
        \\syscall
        : [ret] "={rax}" (-> i64),
        : [nr] "{rax}" (args.nr), [arg0] "{rdi}" (args.arg0), [arg1] "{rsi}" (args.arg1),
          [arg2] "{rdx}" (args.arg2), [arg3] "{r10}" (args.arg3), [arg4] "{r8}" (args.arg4), [arg5] "{r9}" (args.arg5),
    );
}
