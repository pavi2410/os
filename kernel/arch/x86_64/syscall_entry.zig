const cpu = @import("cpu.zig");
const gdt = @import("gdt.zig");
const handlers = @import("../../syscall/handlers.zig");
const hal = @import("../../hal.zig");
const smp = @import("smp.zig");

const EFER_MSR: u32 = 0xC0000080;
const STAR_MSR: u32 = 0xC0000081;
const LSTAR_MSR: u32 = 0xC0000082;
const SFMASK_MSR: u32 = 0xC0000084;

extern fn syscall_entry() callconv(.{ .x86_64_sysv = .{} }) void;

comptime {
    if (@sizeOf(handlers.Frame) != 128 or @offsetOf(handlers.Frame, "user_rsp") != 120) @compileError("x86 syscall frame layout mismatch");
    if (smp.syscall_user_rsp_offset != 8) @compileError("syscall stub expects CpuLocal.syscall_user_rsp at %gs:8");
    // User %rsp is saved in per-CPU CpuLocal.syscall_user_rsp (%gs:8) before switching
    // to the kernel stack at %gs:0, so concurrent syscalls on other CPUs cannot clobber it.
    asm (
        \\.global syscall_entry
        \\.type syscall_entry, @function
        \\syscall_entry:
        \\  mov %rsp, %gs:8
        \\  mov %gs:0, %rsp
        \\  pushq %gs:8; push %r11; push %rcx; push %rax; push %rdi; push %rsi; push %rdx; push %r10; push %r8; push %r9; push %rbx; push %rbp; push %r12; push %r13; push %r14; push %r15
        \\  mov %rsp, %rdi; call syscall_dispatch
        \\  pop %r15; pop %r14; pop %r13; pop %r12; pop %rbp; pop %rbx; pop %r9; pop %r8; pop %r10; pop %rdx; pop %rsi; pop %rdi; add $8, %rsp; pop %rcx; pop %r11; pop %rsp
        \\  cmp $0xFFFFFFFF80000000, %rcx; jae 2f; sysretq
        \\2: push %r11; popfq; jmp *%rcx
    );
}

pub fn init() void {
    const star: u64 = (@as(u64, gdt.kernel_data_selector) << 48) | (@as(u64, gdt.kernel_code_selector) << 32);
    cpu.wrmsr(EFER_MSR, cpu.rdmsr(EFER_MSR) | 1);
    cpu.wrmsr(STAR_MSR, star);
    cpu.wrmsr(LSTAR_MSR, @intFromPtr(&syscall_entry));
    cpu.wrmsr(SFMASK_MSR, 1 << 9);
    hal.console.println("syscall/sysret entry configured (Linux x86_64 ABI)", .{});
}
