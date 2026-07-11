const std = @import("std");
const io = @import("io.zig");
const process = @import("process.zig");

fn call(message: []const u8, return_address: ?usize) noreturn {
    io.writeStr("\n!!! USER PANIC !!!\n");
    io.writeStr(message);
    io.writeStr("\n");

    if (return_address) |address| {
        io.writeStr("return address: ");
        io.writeU64(address);
        io.writeStr("\n");
    }
    process.exit(127);
}

/// Root panic namespace used by Zig-generated safety checks and `@panic`.
pub const handler = std.debug.FullPanic(call);
