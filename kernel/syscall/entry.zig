const cpu = @import("../arch/x86_64/cpu.zig");
const gdt = @import("../arch/x86_64/gdt.zig");
const handlers = @import("handlers.zig");
const serial = @import("../arch/x86_64/serial.zig");

const EFER_MSR: u32 = 0xC0000080;
const STAR_MSR: u32 = 0xC0000081;
const LSTAR_MSR: u32 = 0xC0000082;
const SFMASK_MSR: u32 = 0xC0000084;

const EFER_SCE: u64 = 1 << 0;
const SFMASK_IF: u64 = 1 << 9;

/// Scratch used by the syscall stub before a kernel stack is available.
/// Safe as plain globals: syscall entry runs with interrupts masked on a
/// single CPU, so there is no reentrancy until we switch stacks.
export var syscall_user_rsp: u64 = 0;

extern fn syscall_entry() callconv(.{ .x86_64_sysv = .{} }) void;

comptime {
    // The stub must not clobber any callee-saved register (rbx, rbp, r12-r15):
    // user code relies on them being preserved across `syscall`. We therefore
    // use memory scratch + the kernel stack instead of spare registers.
    asm (
        \\.global syscall_entry
        \\.type syscall_entry, @function
        \\syscall_entry:
        \\  mov %rsp, syscall_user_rsp(%rip)
        \\  mov gdt_kernel_rsp0(%rip), %rsp
        \\
        \\  pushq syscall_user_rsp(%rip)
        \\  push %r11
        \\  push %rcx
        \\  push %rax
        \\  push %rdi
        \\  push %rsi
        \\  push %rdx
        \\  push %r10
        \\  push %r8
        \\  push %r9
        \\  push %rbx
        \\  push %rbp
        \\  push %r12
        \\  push %r13
        \\  push %r14
        \\  push %r15
        \\  mov %rsp, %rdi
        \\  call syscall_dispatch
        \\
        \\  // rax holds the return value. Restore argument registers from the
        \\  // frame (the dispatcher clobbered them) and callee-saved registers
        \\  // from the values saved at syscall entry.
        \\  pop %r15
        \\  pop %r14
        \\  pop %r13
        \\  pop %r12
        \\  pop %rbp
        \\  pop %rbx
        \\  pop %r9
        \\  pop %r8
        \\  pop %r10
        \\  pop %rdx
        \\  pop %rsi
        \\  pop %rdi
        \\  add $8, %rsp
        \\  pop %rcx
        \\  pop %r11
        \\  pop %rsp
        \\
        \\  cmp $0xFFFFFFFF80000000, %rcx
        \\  jae 2f
        \\  sysretq
        \\2:
        \\  push %r11
        \\  popfq
        \\  jmp *%rcx
    );
}

comptime {
    if (@sizeOf(handlers.Frame) != 128) @compileError("syscall Frame must be 128 bytes");
    if (@offsetOf(handlers.Frame, "rbx") != 40) @compileError("syscall Frame layout mismatch");
    if (@offsetOf(handlers.Frame, "nr") != 96) @compileError("syscall Frame layout mismatch");
    if (@offsetOf(handlers.Frame, "user_rip") != 104) @compileError("syscall Frame layout mismatch");
    if (@offsetOf(handlers.Frame, "user_rflags") != 112) @compileError("syscall Frame layout mismatch");
    if (@offsetOf(handlers.Frame, "user_rsp") != 120) @compileError("syscall Frame layout mismatch");
}

pub fn init() void {
    // SYSCALL loads CS from STAR[47:32] (kernel code) and SS = that + 8.
    // SYSRET loads CS from STAR[63:48] + 16 and SS from STAR[63:48] + 8,
    // so the SYSRET base is the kernel data selector (user data/code follow it).
    const star: u64 =
        (@as(u64, gdt.kernel_data_selector) << 48) |
        (@as(u64, gdt.kernel_code_selector) << 32);

    const efer = cpu.rdmsr(EFER_MSR);
    cpu.wrmsr(EFER_MSR, efer | EFER_SCE);
    cpu.wrmsr(STAR_MSR, star);
    cpu.wrmsr(LSTAR_MSR, @intFromPtr(&syscall_entry));
    cpu.wrmsr(SFMASK_MSR, SFMASK_IF);

    serial.writeString("syscall/sysret entry configured (Linux x86_64 ABI)\r\n");
}
