const std = @import("std");
const acpi_sig = @import("common/acpi_sig");

test "sigEq4At accepts comptime string literal signatures" {
    const table = "XSDT" ++ [_]u8{0} ** 32;
    try std.testing.expect(acpi_sig.sigEq4At(table[0..], 0, "XSDT"));
    try std.testing.expect(!acpi_sig.sigEq4At(table[0..], 0, "RSDT"));
}

test "sigEq8At matches rsdp prefix" {
    var rsdp: [36]u8 = .{0} ** 36;
    @memcpy(rsdp[0..8], "RSD PTR ");
    try std.testing.expect(acpi_sig.sigEq8At(&rsdp, 0, "RSD PTR "));
    try std.testing.expect(!acpi_sig.sigEq8At(&rsdp, 0, "RSDT    "));
}

test "sigEq4Bytes matches runtime signatures" {
    const table = "APIC" ++ [_]u8{0} ** 4;
    try std.testing.expect(acpi_sig.sigEq4Bytes(table[0..], 0, .{ 'A', 'P', 'I', 'C' }));
    try std.testing.expect(!acpi_sig.sigEq4Bytes(table[0..], 0, .{ 'M', 'C', 'F', 'G' }));
}

test "signature helpers honor bounds" {
    const short = [_]u8{ 'X', 'S' };
    try std.testing.expect(!acpi_sig.sigEq4At(&short, 0, "XSDT"));
    try std.testing.expect(!acpi_sig.sigEq8At(&short, 0, "RSD PTR "));
}
