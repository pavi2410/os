const std = @import("std");
const abi_hw = @import("abi_hw");
const hw_format = @import("hw_format");

test "formatCpuinfo emits expected keys" {
    var info = std.mem.zeroes(abi_hw.CpuInfo);
    @memcpy(info.vendor[0..12], "GenuineIntel");
    @memcpy(info.brand[0..8], "Test CPU");
    info.family = 6;
    info.model = 142;
    info.stepping = 10;
    info.apic_id = 1;
    info.logical_cpus = 4;
    info.ioapic_count = 1;

    var buf: [512]u8 = undefined;
    const n = hw_format.formatCpuinfo(&info, &buf);
    const text = buf[0..n];

    try std.testing.expect(std.mem.indexOf(u8, text, "vendor_id\t: GenuineIntel\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cpu family\t: 6\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "model\t: 142\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "model name\t: Test CPU\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "stepping\t: 10\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "apic_id\t: 1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "cpu cores\t: 4\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "ioapic_count\t: 1\n") != null);
}

test "formatIomem line shape" {
    const regions = [_]abi_hw.MemRegionInfo{
        .{ .start = 0, .length = 0x1000, .kind = .conventional },
    };
    var buf: [128]u8 = undefined;
    const n = hw_format.formatIomem(&regions, &buf);
    const text = buf[0..n];
    try std.testing.expect(std.mem.indexOf(u8, text, "0000000000000000-0000000000000fff : conventional\n") != null);
}

test "pci addr format and parse round-trip" {
    var name: [8]u8 = undefined;
    const n = hw_format.formatPciAddr(0x00, 0x1f, 0, &name);
    try std.testing.expectEqualStrings("00:1f.0", name[0..n]);

    var bus: u8 = 0;
    var device: u8 = 0;
    var function: u8 = 0;
    try std.testing.expect(hw_format.parsePciAddr(name[0..n], &bus, &device, &function));
    try std.testing.expectEqual(@as(u8, 0x00), bus);
    try std.testing.expectEqual(@as(u8, 0x1f), device);
    try std.testing.expectEqual(@as(u8, 0), function);
}

test "sysfs hex attribute newline" {
    var buf: [16]u8 = undefined;
    const n = hw_format.formatHexAttr(0x8086, 4, &buf);
    try std.testing.expectEqualStrings("8086\n", buf[0..n]);
}
