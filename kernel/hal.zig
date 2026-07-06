const cpu_arch = @import("arch/x86_64/cpu.zig");
const interrupts = @import("arch/x86_64/interrupts.zig");
const rtc = @import("arch/x86_64/rtc.zig");
const serial = @import("arch/x86_64/serial.zig");

pub const console = struct {
    pub fn init() void {
        serial.init();
    }

    pub fn writeString(s: []const u8) void {
        serial.writeString(s);
    }

    pub fn printf(comptime fmt: []const u8, args: anytype) void {
        serial.printf(fmt, args);
    }
};

pub const processor = struct {
    pub fn haltForever() noreturn {
        cpu_arch.haltForever();
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
