const cpu = @import("cpu.zig");
const exc_frame = @import("frame.zig");
const gdt = @import("gdt.zig");
const interrupts = @import("interrupts.zig");
const std = @import("std");

pub const ExceptionFrame = exc_frame.Frame;

const IdtEntry = extern struct {
    offset_low: u16,
    selector: u16,
    ist: u8,
    type_attr: u8,
    offset_mid: u16,
    offset_high: u32,
    reserved: u32,
};

const IdtPointer = packed struct {
    limit: u16,
    base: u64,
};

const irq_vector_start: usize = 32;
const irq_vector_end: usize = 49; // 32–47 device/timer IRQs, 48 reschedule IPI

var idt: [256]IdtEntry = undefined;

extern fn isr_0() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn isr_6() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn isr_8() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn isr_13() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn isr_14() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn isr_default() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn idt_load(ptr: *const IdtPointer) callconv(.{ .x86_64_sysv = .{} }) void;

extern fn isr_32() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn isr_33() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn isr_34() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn isr_35() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn isr_36() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn isr_37() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn isr_38() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn isr_39() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn isr_40() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn isr_41() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn isr_42() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn isr_43() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn isr_44() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn isr_45() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn isr_46() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn isr_47() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn isr_48() callconv(.{ .x86_64_sysv = .{} }) void;

comptime {
    asm (
        \\.global isr_0
        \\.type isr_0, @function
        \\isr_0:
        \\  cli
        \\  push $0
        \\  push $0
        \\  jmp exception_stub
        \\
        \\.global isr_6
        \\.type isr_6, @function
        \\isr_6:
        \\  cli
        \\  push $0
        \\  push $6
        \\  jmp exception_stub
        \\
        \\.global isr_8
        \\.type isr_8, @function
        \\isr_8:
        \\  cli
        \\  push $0
        \\  push $8
        \\  jmp exception_stub
        \\
        \\.global isr_13
        \\.type isr_13, @function
        \\isr_13:
        \\  cli
        \\  push $13
        \\  jmp exception_stub
        \\
        \\.global isr_14
        \\.type isr_14, @function
        \\isr_14:
        \\  cli
        \\  push $14
        \\  jmp exception_stub
        \\
        \\.global isr_default
        \\.type isr_default, @function
        \\isr_default:
        \\  cli
        \\  push $0
        \\  push $0
        \\  jmp exception_stub
        \\
        \\.global exception_stub
        \\.type exception_stub, @function
        \\exception_stub:
        \\  push %r15
        \\  push %r14
        \\  push %r13
        \\  push %r12
        \\  push %r11
        \\  push %r10
        \\  push %r9
        \\  push %r8
        \\  push %rsi
        \\  push %rdi
        \\  push %rbp
        \\  push %rdx
        \\  push %rcx
        \\  push %rbx
        \\  push %rax
        \\  mov %rsp, %rdi
        \\  call exception_dispatch
        \\  test %al, %al
        \\  jz 1f
        \\  pop %rax
        \\  pop %rbx
        \\  pop %rcx
        \\  pop %rdx
        \\  pop %rbp
        \\  pop %rdi
        \\  pop %rsi
        \\  pop %r8
        \\  pop %r9
        \\  pop %r10
        \\  pop %r11
        \\  pop %r12
        \\  pop %r13
        \\  pop %r14
        \\  pop %r15
        \\  add $16, %rsp
        \\  iretq
        \\1:
        \\  hlt
        \\  jmp 1b
        \\
        \\.global irq_stub
        \\.type irq_stub, @function
        \\irq_stub:
        \\  push %r15
        \\  push %r14
        \\  push %r13
        \\  push %r12
        \\  push %r11
        \\  push %r10
        \\  push %r9
        \\  push %r8
        \\  push %rsi
        \\  push %rdi
        \\  push %rbp
        \\  push %rdx
        \\  push %rcx
        \\  push %rbx
        \\  push %rax
        \\  mov %rsp, %rdi
        \\  call irq_dispatch
        \\  pop %rax
        \\  pop %rbx
        \\  pop %rcx
        \\  pop %rdx
        \\  pop %rbp
        \\  pop %rdi
        \\  pop %rsi
        \\  pop %r8
        \\  pop %r9
        \\  pop %r10
        \\  pop %r11
        \\  pop %r12
        \\  pop %r13
        \\  pop %r14
        \\  pop %r15
        \\  add $16, %rsp
        \\  iretq
        \\
        \\.global idt_load
        \\.type idt_load, @function
        \\idt_load:
        \\  lidt (%rdi)
        \\  retq
    );

    for (irq_vector_start..irq_vector_end) |vector| {
        const stub = std.fmt.comptimePrint(
            \\.global isr_{d}
            \\.type isr_{d}, @function
            \\isr_{d}:
            \\  cli
            \\  push $0
            \\  push ${d}
            \\  jmp irq_stub
            \\
        , .{ vector, vector, vector, vector });
        asm (stub);
    }
}

export fn exception_dispatch(frame: *ExceptionFrame) callconv(.{ .x86_64_sysv = .{} }) u8 {
    return @intFromBool(interrupts.dispatchException(frame));
}

export fn irq_dispatch(frame: *ExceptionFrame) callconv(.{ .x86_64_sysv = .{} }) void {
    interrupts.dispatchIrq(frame);
}

fn setHandler(
    vector: usize,
    handler: *const fn () callconv(.{ .x86_64_sysv = .{} }) void,
    ist: u8,
) void {
    const address = @intFromPtr(handler);
    idt[vector] = .{
        .offset_low = @truncate(address),
        .selector = gdt.kernel_code_selector,
        .ist = ist,
        .type_attr = 0x8E,
        .offset_mid = @truncate(address >> 16),
        .offset_high = @truncate(address >> 32),
        .reserved = 0,
    };
}

fn irqHandler(vector: usize) *const fn () callconv(.{ .x86_64_sysv = .{} }) void {
    return switch (vector) {
        32 => isr_32,
        33 => isr_33,
        34 => isr_34,
        35 => isr_35,
        36 => isr_36,
        37 => isr_37,
        38 => isr_38,
        39 => isr_39,
        40 => isr_40,
        41 => isr_41,
        42 => isr_42,
        43 => isr_43,
        44 => isr_44,
        45 => isr_45,
        46 => isr_46,
        47 => isr_47,
        48 => isr_48,
        else => isr_default,
    };
}

pub fn init() void {
    @memset(std.mem.asBytes(&idt), 0);
    for (0..256) |vector| {
        setHandler(vector, isr_default, 0);
    }
    // Use RSP0 (IST=0) for exception delivery. A prior TSS layout bug left IST1
    // null; keep exceptions on RSP0 until IST delivery is re-validated.
    setHandler(0, isr_0, 0);
    setHandler(6, isr_6, 0);
    setHandler(8, isr_8, 0);
    setHandler(13, isr_13, 0);
    setHandler(14, isr_14, 0);

    for (irq_vector_start..irq_vector_end) |vector| {
        setHandler(vector, irqHandler(vector), 0);
    }
}

pub fn load() void {
    const ptr = IdtPointer{
        .limit = @sizeOf(@TypeOf(idt)) - 1,
        .base = @intFromPtr(&idt),
    };
    idt_load(&ptr);
}

