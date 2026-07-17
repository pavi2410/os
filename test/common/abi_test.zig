const std = @import("std");
const abi_fs = @import("abi_fs");
const abi_hw = @import("abi_hw");
const abi_net = @import("abi_net");
const abi_syscall = @import("abi_syscall");

test "syscall numbers stay Linux-compatible for implemented calls" {
    try std.testing.expectEqual(@as(comptime_int, 0), abi_syscall.read);
    try std.testing.expectEqual(@as(comptime_int, 1), abi_syscall.write);
    try std.testing.expectEqual(@as(comptime_int, 24), abi_syscall.sched_yield);
    try std.testing.expectEqual(@as(comptime_int, 57), abi_syscall.fork);
    try std.testing.expectEqual(@as(comptime_int, 13), abi_syscall.rt_sigaction);
    try std.testing.expectEqual(@as(comptime_int, 14), abi_syscall.rt_sigprocmask);
    try std.testing.expectEqual(@as(comptime_int, 62), abi_syscall.kill);
    try std.testing.expectEqual(@as(comptime_int, 82), abi_syscall.rename);
    try std.testing.expectEqual(@as(comptime_int, 88), abi_syscall.symlink);
    try std.testing.expectEqual(@as(comptime_int, 89), abi_syscall.readlink);
    try std.testing.expectEqual(@as(comptime_int, 165), abi_syscall.mount);
    try std.testing.expectEqual(@as(comptime_int, 166), abi_syscall.umount2);
    try std.testing.expectEqual(@as(comptime_int, 228), abi_syscall.clock_gettime);
    try std.testing.expectEqual(@as(comptime_int, 1024), abi_syscall.getnetconfig);
    try std.testing.expectEqual(@as(comptime_int, 1025), abi_syscall.getneighbors);
}

test "filesystem ABI layouts match syscall handlers" {
    try std.testing.expectEqual(@as(usize, 128), @sizeOf(abi_fs.Stat));
    try std.testing.expectEqual(@as(usize, 19), abi_fs.dirent64_name_offset);
    try std.testing.expectEqual(@as(u32, 0o100), abi_fs.O_CREAT);
    try std.testing.expectEqual(@as(u32, 0o040000), abi_fs.S_IFDIR);
}

test "dirent64 helpers round-trip records" {
    var buf: [64]u8 = undefined;
    abi_fs.writeDirent64(&buf, 42, 7, abi_fs.DT_REG, "foo.txt");
    try std.testing.expectEqual(@as(usize, 32), abi_fs.dirent64Reclen("foo.txt".len));

    var it = abi_fs.Dirent64Iterator{ .data = &buf };
    const entry = it.next().?;
    try std.testing.expectEqual(@as(u64, 42), entry.header.d_ino);
    try std.testing.expectEqual(@as(i64, 7), entry.header.d_off);
    try std.testing.expectEqual(@as(u16, 32), entry.header.d_reclen);
    try std.testing.expectEqual(abi_fs.DT_REG, entry.header.d_type);
    try std.testing.expectEqualStrings("foo.txt", entry.name);
    try std.testing.expect(it.next() == null);
}

test "network ABI sockaddr uses big-endian port" {
    const addr = abi_net.sockaddrIn(.{ 10, 0, 2, 2 }, 8080);
    try std.testing.expectEqual(abi_net.AF_INET, addr.family);
    try std.testing.expectEqual(@byteSwap(@as(u16, 8080)), addr.port_be);
    try std.testing.expectEqual(@as(u8, 10), addr.addr[0]);
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(abi_net.SockaddrIn));
    try std.testing.expectEqual(@as(usize, 22), @sizeOf(abi_net.NetConfig));
}

test "hardware info layouts used by procfs formatters" {
    try std.testing.expectEqual(@as(usize, 92), @sizeOf(abi_hw.CpuInfo));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(abi_hw.CpuInfo, "vendor"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(abi_hw.CpuInfo, "brand"));
    try std.testing.expectEqual(@as(usize, 80), @offsetOf(abi_hw.CpuInfo, "logical_cpus"));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(abi_hw.MemRegionInfo));
}
