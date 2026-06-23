const cpu = @import("cpu.zig");
const gdt = @import("gdt.zig");
const serial = @import("serial.zig");
const std = @import("std");

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

pub const ExceptionFrame = extern struct {
    rax: u64,
    rbx: u64,
    rcx: u64,
    rdx: u64,
    rbp: u64,
    rdi: u64,
    rsi: u64,
    r8: u64,
    r9: u64,
    r10: u64,
    r11: u64,
    r12: u64,
    r13: u64,
    r14: u64,
    r15: u64,
    vector: u64,
    error_code: u64,
    rip: u64,
    cs: u64,
    rflags: u64,
};

var idt: [256]IdtEntry = undefined;

extern fn isr_13() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn isr_14() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn isr_default() callconv(.{ .x86_64_sysv = .{} }) void;
extern fn idt_load(ptr: *const IdtPointer) callconv(.{ .x86_64_sysv = .{} }) void;

comptime {
    asm (
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
        \\1:
        \\  hlt
        \\  jmp 1b
        \\
        \\.global idt_load
        \\.type idt_load, @function
        \\idt_load:
        \\  lidt (%rdi)
        \\  retq
    );
}

export fn exception_dispatch(frame: *ExceptionFrame) callconv(.{ .x86_64_sysv = .{} }) void {
    switch (frame.vector) {
        13 => handleGeneralProtectionFault(frame),
        14 => handlePageFault(frame),
        else => handleDefault(frame),
    }
}

fn handlePageFault(frame: *ExceptionFrame) void {
    const cr2 = readCr2();
    serial.writeString("\r\n!!! Page Fault !!!\r\n");
    serial.printf("CR2:  0x{x}\r\n", .{cr2});
    serial.printf("RIP:  0x{x}\r\n", .{frame.rip});
    serial.printf("Code: 0x{x}\r\n", .{frame.error_code});
    haltForever();
}

fn handleGeneralProtectionFault(frame: *ExceptionFrame) void {
    serial.writeString("\r\n!!! General Protection Fault !!!\r\n");
    serial.printf("RIP:  0x{x}\r\n", .{frame.rip});
    serial.printf("Code: 0x{x}\r\n", .{frame.error_code});
    haltForever();
}

fn handleDefault(frame: *ExceptionFrame) void {
    serial.writeString("\r\n!!! Unhandled Exception !!!\r\n");
    serial.printf("Vector: {d}\r\n", .{frame.vector});
    serial.printf("RIP:    0x{x}\r\n", .{frame.rip});
    serial.printf("Code:   0x{x}\r\n", .{frame.error_code});
    haltForever();
}

fn haltForever() noreturn {
    while (true) cpu.hlt();
}

fn readCr2() u64 {
    return asm volatile ("mov %%cr2, %[result]"
        : [result] "=r" (-> u64),
    );
}

fn setHandler(vector: usize, handler: *const fn () callconv(.{ .x86_64_sysv = .{} }) void) void {
    const address = @intFromPtr(handler);
    idt[vector] = .{
        .offset_low = @truncate(address),
        .selector = gdt.kernel_code_selector,
        .ist = 0,
        .type_attr = 0x8E,
        .offset_mid = @truncate(address >> 16),
        .offset_high = @truncate(address >> 32),
        .reserved = 0,
    };
}

pub fn init() void {
    @memset(std.mem.asBytes(&idt), 0);
    for (0..256) |vector| {
        setHandler(vector, isr_default);
    }
    setHandler(13, isr_13);
    setHandler(14, isr_14);
}

pub fn load() void {
    const ptr = IdtPointer{
        .limit = @sizeOf(@TypeOf(idt)) - 1,
        .base = @intFromPtr(&idt),
    };
    idt_load(&ptr);
}
