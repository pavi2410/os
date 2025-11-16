const serial = @import("serial.zig");
const boot_info = @import("boot_info");

/// Kernel entry point
/// Called by bootloader with boot information in RDI register
export fn _start(boot_info_ptr: *const boot_info.BootInfo) callconv(.{ .x86_64_sysv = .{} }) noreturn {
    // Initialize serial port
    serial.init();

    // Print welcome message
    serial.writeString("\r\n=== Kernel Entry ===\r\n");
    serial.printf("Memory map: {d} descriptors, size: {d} bytes\r\n", .{
        boot_info_ptr.memory_map.count,
        boot_info_ptr.memory_map.size,
    });
    serial.printf("Descriptor size: {d}, version: {d}\r\n", .{
        boot_info_ptr.memory_map.descriptor_size,
        boot_info_ptr.memory_map.descriptor_version,
    });

    // Write to VGA for visual confirmation
    const vga: [*]volatile u16 = @ptrFromInt(0xb8000);
    vga[0] = 0x2F4B; // 'K' in green
    vga[1] = 0x2F4F; // 'O'
    vga[2] = 0x2F4B; // 'K'

    serial.writeString("Kernel initialized. Halting.\r\n");

    while (true) asm volatile ("hlt");
}
