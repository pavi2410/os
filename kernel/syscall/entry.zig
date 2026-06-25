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

extern fn syscall_entry() callconv(.{ .x86_64_sysv = .{} }) void;

comptime {
    asm (
        \\.global syscall_entry
        \\.type syscall_entry, @function
        \\syscall_entry:
        \\  push %r11
        \\  push %rcx
        \\  push %rax
        \\  push %rdi
        \\  push %rsi
        \\  push %rdx
        \\  push %r10
        \\  push %r8
        \\  push %r9
        \\  mov %rsp, %rdi
        \\  call syscall_dispatch
        \\  add $56, %rsp
        \\  pop %rcx
        \\  pop %r11
        \\  mov $0xFFFFFFFF80000000, %rdx
        \\  cmp %rdx, %rcx
        \\  jb 1f
        \\  push %r11
        \\  popfq
        \\  jmp *%rcx
        \\1:
        \\  sysretq
    );
}

comptime {
    if (@sizeOf(handlers.Frame) != 72) @compileError("syscall Frame must be 72 bytes");
    if (@offsetOf(handlers.Frame, "nr") != 48) @compileError("syscall Frame layout mismatch");
    if (@offsetOf(handlers.Frame, "user_rip") != 56) @compileError("syscall Frame layout mismatch");
    if (@offsetOf(handlers.Frame, "user_rflags") != 64) @compileError("syscall Frame layout mismatch");
}

pub fn init() void {
    const star: u64 =
        (@as(u64, gdt.kernel_code_selector) << 48) |
        (@as(u64, gdt.user_code_selector) << 32);

    const efer = cpu.rdmsr(EFER_MSR);
    cpu.wrmsr(EFER_MSR, efer | EFER_SCE);
    cpu.wrmsr(STAR_MSR, star);
    cpu.wrmsr(LSTAR_MSR, @intFromPtr(&syscall_entry));
    cpu.wrmsr(SFMASK_MSR, SFMASK_IF);

    serial.writeString("syscall/sysret entry configured (Linux x86_64 ABI)\r\n");
}
