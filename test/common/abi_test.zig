const std = @import("std");
const abi_fs = @import("abi_fs");
const abi_net = @import("abi_net");
const abi_syscall = @import("abi_syscall");

test "syscall numbers stay Linux-compatible for implemented calls" {
    try std.testing.expectEqual(@as(comptime_int, 0), abi_syscall.read);
    try std.testing.expectEqual(@as(comptime_int, 1), abi_syscall.write);
    try std.testing.expectEqual(@as(comptime_int, 57), abi_syscall.fork);
    try std.testing.expectEqual(@as(comptime_int, 228), abi_syscall.clock_gettime);
    try std.testing.expectEqual(@as(comptime_int, 1024), abi_syscall.getnetconfig);
}

test "filesystem ABI layouts match syscall handlers" {
    try std.testing.expectEqual(@as(usize, 128), @sizeOf(abi_fs.Stat));
    try std.testing.expectEqual(@as(usize, 19), abi_fs.dirent64_name_offset);
    try std.testing.expectEqual(@as(u32, 0o100), abi_fs.O_CREAT);
    try std.testing.expectEqual(@as(u32, 0o040000), abi_fs.S_IFDIR);
}

test "network ABI sockaddr uses big-endian port" {
    const addr = abi_net.sockaddrIn(.{ 10, 0, 2, 2 }, 8080);
    try std.testing.expectEqual(abi_net.AF_INET, addr.family);
    try std.testing.expectEqual(@byteSwap(@as(u16, 8080)), addr.port_be);
    try std.testing.expectEqual(@as(u8, 10), addr.addr[0]);
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(abi_net.SockaddrIn));
    try std.testing.expectEqual(@as(usize, 22), @sizeOf(abi_net.NetConfig));
}
