pub const syscall = @import("syscall.zig");
pub const dns = @import("dns.zig");

comptime {
    _ = @import("start.zig");
}
