const std = @import("std");
const cpu_arch = @import("arch/x86_64/cpu.zig");
const interrupts = @import("arch/x86_64/interrupts.zig");
const rtc = @import("arch/x86_64/rtc.zig");
const serial = @import("arch/x86_64/serial.zig");

pub const console = struct {
    pub fn init() void {
        serial.init();
    }

    pub fn writer() *std.Io.Writer {
        return serial.writer();
    }

    pub fn print(comptime fmt: []const u8, args: anytype) void {
        serial.print(fmt, args);
    }

    pub fn println(comptime fmt: []const u8, args: anytype) void {
        serial.println(fmt, args);
    }

    pub fn writeAll(bytes: []const u8) void {
        serial.writeAll(bytes);
    }
};

pub const processor = struct {
    pub fn haltForever() noreturn {
        cpu_arch.haltForever();
    }

    pub fn relaxInterruptible() void {
        cpu_arch.relaxInterruptible();
    }
};

pub const clock = struct {
    pub fn realtimeSeconds() i64 {
        return rtc.realtimeSeconds();
    }

    pub fn timerTickCount() u64 {
        return interrupts.timerTickCount();
    }
};
