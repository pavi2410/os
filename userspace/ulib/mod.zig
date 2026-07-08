//! Userland library: Linux ABI syscalls, CRT (`_start`), and helpers for `/BIN/*` programs.
//! Not glibc and not Zig's `std`.
pub const syscall = @import("syscall.zig");
pub const string = @import("string.zig");
pub const path = @import("path.zig");
pub const environ = @import("environ.zig");
pub const dns = @import("dns.zig");
pub const format = @import("format.zig");
pub const fs = @import("fs.zig");
pub const io = @import("io.zig");
pub const ip = @import("ip.zig");
pub const net = @import("net.zig");
pub const parse = @import("parse.zig");
pub const process = @import("process.zig");
pub const signal = @import("signal.zig");
pub const time = @import("time.zig");
pub const hw = @import("hw.zig");

comptime {
    if (@import("builtin").os.tag != .linux) {
        _ = @import("start.zig");
    }
}
