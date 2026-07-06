const ipv4 = @import("ipv4.zig");

/// QEMU user-mode networking defaults (10.0.2.0/24).
pub const guest_ip = ipv4.Addr{ 10, 0, 2, 15 };
pub const gateway_ip = ipv4.Addr{ 10, 0, 2, 2 };
pub const dns_ip = ipv4.Addr{ 10, 0, 2, 3 };
