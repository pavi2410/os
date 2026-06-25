const apic = @import("apic.zig");
const cpu = @import("cpu.zig");
const serial = @import("serial.zig");

pub const Frame = extern struct {
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

pub const HandlerFn = *const fn (vector: u8) void;

const irq_vector_end: usize = 48;

var irq_handlers: [256]?HandlerFn = [_]?HandlerFn{null} ** 256;
var timer_ticks: u64 = 0;

pub fn registerIrq(vector: u8, handler: HandlerFn) void {
    irq_handlers[vector] = handler;
}

pub fn timerTickCount() u64 {
    const ptr: *volatile u64 = &timer_ticks;
    return ptr.*;
}

pub fn dispatchException(frame: *Frame) void {
    switch (frame.vector) {
        13 => handleGeneralProtectionFault(frame),
        14 => handlePageFault(frame),
        else => handleDefaultException(frame),
    }
}

pub fn dispatchIrq(frame: *Frame) void {
    const vector: u8 = @truncate(frame.vector);

    if (vector >= apic.irq_vector_base and vector < irq_vector_end) {
        if (irq_handlers[vector]) |handler| {
            handler(vector);
            return;
        }
    }

    handleUnhandledIrq(vector);
}

fn handlePageFault(frame: *Frame) void {
    const cr2 = readCr2();
    serial.writeString("\r\n!!! Page Fault !!!\r\n");
    serial.printf("CR2:  0x{x}\r\n", .{cr2});
    serial.printf("RIP:  0x{x}\r\n", .{frame.rip});
    serial.printf("Code: 0x{x}\r\n", .{frame.error_code});
    haltForever();
}

fn handleGeneralProtectionFault(frame: *Frame) void {
    serial.writeString("\r\n!!! General Protection Fault !!!\r\n");
    serial.printf("RIP:  0x{x}\r\n", .{frame.rip});
    serial.printf("Code: 0x{x}\r\n", .{frame.error_code});
    haltForever();
}

fn handleDefaultException(frame: *Frame) void {
    serial.writeString("\r\n!!! Unhandled Exception !!!\r\n");
    serial.printf("Vector: {d}\r\n", .{frame.vector});
    serial.printf("RIP:    0x{x}\r\n", .{frame.rip});
    serial.printf("Code:   0x{x}\r\n", .{frame.error_code});
    haltForever();
}

fn handleUnhandledIrq(vector: u8) void {
    serial.printf("\r\n!!! Unhandled IRQ vector {d} !!!\r\n", .{vector});
    if (vector >= apic.irq_vector_base and vector < irq_vector_end) {
        apic.lapicEoi();
    }
}

pub fn timerIrqHandler(vector: u8) void {
    _ = vector;
    const ptr: *volatile u64 = &timer_ticks;
    ptr.* += 1;
    apic.lapicEoi();
}

fn readCr2() u64 {
    return asm volatile ("mov %%cr2, %[result]"
        : [result] "=r" (-> u64),
    );
}

fn haltForever() noreturn {
    while (true) cpu.hlt();
}
