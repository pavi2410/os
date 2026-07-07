const std = @import("std");
const pci_class = @import("pci_class");

test "pci class enums name known devices" {
    try std.testing.expectEqual(@as(u8, 0x02), @intFromEnum(pci_class.PciClass.network));
    try std.testing.expectEqualStrings("Network", pci_class.className(0x02, 0x00));
    try std.testing.expectEqualStrings("Display", pci_class.className(0x03, 0x00));
    try std.testing.expectEqualStrings("Bridge", pci_class.className(0x06, 0x00));
}

test "storage subclasses stay specific" {
    try std.testing.expectEqualStrings("NVMe storage", pci_class.className(0x01, 0x08));
    try std.testing.expectEqualStrings("SCSI storage", pci_class.className(0x01, 0x00));
    try std.testing.expectEqualStrings("Mass storage", pci_class.className(0x01, 0x05));
}

test "unknown pci classes fall back to Device" {
    try std.testing.expectEqualStrings("Device", pci_class.className(0xFF, 0x00));
}
