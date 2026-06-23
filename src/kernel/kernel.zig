const serial = @import("serial.zig");
const shared = @import("shared");

var boot_info: *const shared.BootInfo = undefined;

pub fn init(bi: *const shared.BootInfo) void {
    boot_info = bi;

    serial.init();

    serial.writeString("\r\n=== Kernel Entry ===\r\n");
    serial.printf("Memory map: {d} descriptors, size: {d} bytes\r\n", .{
        boot_info.memory_map.count,
        boot_info.memory_map.size,
    });
    serial.printf("Descriptor size: {d}, version: {d}\r\n", .{
        boot_info.memory_map.descriptor_size,
        boot_info.memory_map.descriptor_version,
    });

    const vga: [*]volatile u16 = @ptrFromInt(0xb8000);
    vga[0] = 0x2F4B; // 'K' in green
    vga[1] = 0x2F4F; // 'O'
    vga[2] = 0x2F4B; // 'K'

    serial.writeString("Kernel initialized. Halting.\r\n");
}

pub fn run() noreturn {
    while (true) asm volatile ("hlt");
}
