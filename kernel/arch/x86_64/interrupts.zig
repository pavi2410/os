const apic = @import("apic.zig");
const cow = @import("../../mm/cow.zig");
const demand = @import("../../mm/demand.zig");
const cpu = @import("cpu.zig");
const crash = @import("../../proc/crash.zig");
const exc_frame = @import("frame.zig");
const scheduler = @import("../../proc/scheduler.zig");
const serial = @import("serial.zig");
const std = @import("std");

pub const Frame = exc_frame.Frame;

pub const HandlerFn = *const fn (vector: u8) void;

const irq_vector_end: usize = 50;

var irq_handlers: [256]?HandlerFn = [_]?HandlerFn{null} ** 256;
var timer_ticks = std.atomic.Value(u64).init(0);

pub fn registerIrq(vector: u8, handler: HandlerFn) void {
    irq_handlers[vector] = handler;
}

pub fn timerTickCount() u64 {
    return timer_ticks.load(.monotonic);
}

pub fn dispatchException(frame_ptr: *Frame) bool {
    if (frame_ptr.cs & 3 == 3) {
        return handleUserException(frame_ptr);
    }

    switch (frame_ptr.vector) {
        8 => handleDoubleFault(frame_ptr),
        13 => handleGeneralProtectionFault(frame_ptr),
        14 => handlePageFault(frame_ptr),
        else => handleDefaultException(frame_ptr),
    }
    unreachable;
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

fn handleUserException(frame_ptr: *Frame) bool {
    if (frame_ptr.vector == 14) {
        const cr2 = readCr2();
        // Order: COW promotion for present RO shared pages, then demand-zero
        // for non-present anonymous/heap/stack VMAs. Unmapped gaps (including
        // the stack guard page below the stack VMA) still terminate the process.
        if (cow.tryHandleUserPageFault(cr2, frame_ptr.error_code)) return true;
        if (demand.tryHandleUserPageFault(cr2, frame_ptr.error_code)) return true;
    }

    const info = crash.Info{
        .vector = frame_ptr.vector,
        .error_code = frame_ptr.error_code,
        .fault_addr = if (frame_ptr.vector == 14) readCr2() else null,
    };
    crash.handleUserFault(frame_ptr, info);
    unreachable;
}

fn handleDoubleFault(frame_ptr: *Frame) void {
    serial.println("\n!!! Double Fault !!!", .{});
    serial.println("RIP:  0x{x}", .{frame_ptr.rip});
    serial.println("Code: 0x{x}", .{frame_ptr.error_code});
    haltForever();
}

fn handlePageFault(frame_ptr: *Frame) void {
    const cr2 = readCr2();
    serial.println("\n!!! Page Fault !!!", .{});
    serial.println("CR2:  0x{x}", .{cr2});
    serial.println("RIP:  0x{x}", .{frame_ptr.rip});
    serial.println("Code: 0x{x}", .{frame_ptr.error_code});
    haltForever();
}

fn handleGeneralProtectionFault(frame_ptr: *Frame) void {
    serial.println("\n!!! General Protection Fault !!!", .{});
    serial.println("RIP:  0x{x}", .{frame_ptr.rip});
    serial.println("Code: 0x{x}", .{frame_ptr.error_code});
    haltForever();
}

fn handleDefaultException(frame_ptr: *Frame) void {
    serial.println("\n!!! Unhandled Exception !!!", .{});
    serial.println("Vector: {d}", .{frame_ptr.vector});
    serial.println("RIP:    0x{x}", .{frame_ptr.rip});
    serial.println("Code:   0x{x}", .{frame_ptr.error_code});
    haltForever();
}

fn handleUnhandledIrq(vector: u8) void {
    serial.println("\n!!! Unhandled IRQ vector {d} !!!", .{vector});
    if (vector >= apic.irq_vector_base and vector < irq_vector_end) {
        apic.lapicEoi();
    }
}

pub fn timerIrqHandler(vector: u8) void {
    _ = vector;
    _ = timer_ticks.fetchAdd(1, .monotonic);
    apic.lapicEoi();
    scheduler.onTimerTick();
    scheduler.scheduleFromIrq();
}

fn readCr2() u64 {
    return asm volatile ("mov %%cr2, %[result]"
        : [result] "=r" (-> u64),
    );
}

fn haltForever() noreturn {
    while (true) cpu.hlt();
}
