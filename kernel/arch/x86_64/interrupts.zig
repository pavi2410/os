const apic = @import("apic.zig");
const cpu = @import("cpu.zig");
const crash = @import("../../proc/crash.zig");
const exc_frame = @import("frame.zig");
const scheduler = @import("../../proc/scheduler.zig");
const serial = @import("serial.zig");
const std = @import("std");

pub const Frame = exc_frame.Frame;

pub const HandlerFn = *const fn (vector: u8) void;

const irq_vector_end: usize = 48;

var irq_handlers: [256]?HandlerFn = [_]?HandlerFn{null} ** 256;
var timer_ticks = std.atomic.Value(u64).init(0);

pub fn registerIrq(vector: u8, handler: HandlerFn) void {
    irq_handlers[vector] = handler;
}

pub fn timerTickCount() u64 {
    return timer_ticks.load(.monotonic);
}

pub fn dispatchException(frame_ptr: *Frame) void {
    if (frame_ptr.cs & 3 == 3) {
        handleUserException(frame_ptr);
        return;
    }

    switch (frame_ptr.vector) {
        8 => handleDoubleFault(frame_ptr),
        13 => handleGeneralProtectionFault(frame_ptr),
        14 => handlePageFault(frame_ptr),
        else => handleDefaultException(frame_ptr),
    }
}

pub fn dispatchIrq(frame_ptr: *Frame) void {
    const vector: u8 = @truncate(frame_ptr.vector);

    if (vector >= apic.irq_vector_base and vector < irq_vector_end) {
        if (irq_handlers[vector]) |handler| {
            handler(vector);
            return;
        }
    }

    handleUnhandledIrq(vector);
}

fn handleUserException(frame_ptr: *Frame) void {
    const info = crash.Info{
        .vector = frame_ptr.vector,
        .error_code = frame_ptr.error_code,
        .fault_addr = if (frame_ptr.vector == 14) readCr2() else null,
    };
    crash.handleUserFault(frame_ptr, info);
}

fn handleDoubleFault(frame_ptr: *Frame) void {
    serial.writeString("\r\n!!! Double Fault !!!\r\n");
    serial.printf("RIP:  0x{x}\r\n", .{frame_ptr.rip});
    serial.printf("Code: 0x{x}\r\n", .{frame_ptr.error_code});
    haltForever();
}

fn handlePageFault(frame_ptr: *Frame) void {
    const cr2 = readCr2();
    serial.writeString("\r\n!!! Page Fault !!!\r\n");
    serial.printf("CR2:  0x{x}\r\n", .{cr2});
    serial.printf("RIP:  0x{x}\r\n", .{frame_ptr.rip});
    serial.printf("Code: 0x{x}\r\n", .{frame_ptr.error_code});
    haltForever();
}

fn handleGeneralProtectionFault(frame_ptr: *Frame) void {
    serial.writeString("\r\n!!! General Protection Fault !!!\r\n");
    serial.printf("RIP:  0x{x}\r\n", .{frame_ptr.rip});
    serial.printf("Code: 0x{x}\r\n", .{frame_ptr.error_code});
    haltForever();
}

fn handleDefaultException(frame_ptr: *Frame) void {
    serial.writeString("\r\n!!! Unhandled Exception !!!\r\n");
    serial.printf("Vector: {d}\r\n", .{frame_ptr.vector});
    serial.printf("RIP:    0x{x}\r\n", .{frame_ptr.rip});
    serial.printf("Code:   0x{x}\r\n", .{frame_ptr.error_code});
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
    _ = timer_ticks.fetchAdd(1, .monotonic);
    apic.lapicEoi();
    scheduler.onTimerTick();
}

fn readCr2() u64 {
    return asm volatile ("mov %%cr2, %[result]"
        : [result] "=r" (-> u64),
    );
}

fn haltForever() noreturn {
    while (true) cpu.hlt();
}
