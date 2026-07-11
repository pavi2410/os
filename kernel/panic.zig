const std = @import("std");
const cpu = @import("arch/x86_64/cpu.zig");
const serial = @import("arch/x86_64/serial.zig");

var panicking = false;

fn call(message: []const u8, return_address: ?usize) noreturn {
    cpu.cli();
    if (panicking) cpu.haltForever();
    panicking = true;

    serial.writeAll("\n!!! KERNEL PANIC !!!\n");
    serial.writeAll(message);
    serial.writeAll("\n");
    if (return_address) |address| {
        serial.println("return address: 0x{x}", .{address});
    }
    cpu.haltForever();
}

/// Root panic namespace used by Zig-generated safety checks and `@panic`.
pub const handler = std.debug.FullPanic(call);
