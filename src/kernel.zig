const std = @import("std");

const uefi = @import("uefi.zig");
const serial = @import("serial.zig");
const MemoryMapInfo = uefi.MemoryMapInfo;

pub fn kernel_entry(mem_map: MemoryMapInfo) noreturn {
    // Initialize serial port
    serial.init();

    // Print welcome message to serial
    serial.writeString("\r\n=== Kernel Entry ===\r\n");
    serial.printf("Memory map: {d} descriptors, size: {d} bytes\r\n", .{
        mem_map.desc_count,
        mem_map.mmap_size,
    });
    serial.printf("Descriptor size: {d}, version: {d}\r\n", .{
        mem_map.desc_size,
        mem_map.desc_version,
    });

    // Also print to VGA for visual confirmation
    const vga: [*]volatile u16 = @ptrFromInt(0xb8000);
    vga[0] = 0x2F4B; // 'K' in green
    vga[1] = 0x2F4F; // 'O'
    vga[2] = 0x2F4B; // 'K'

    serial.writeString("Kernel initialized. Halting.\r\n");

    while (true) asm volatile ("hlt");
}
