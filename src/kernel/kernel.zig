const cpu = @import("arch/x86_64/cpu.zig");
const gdt = @import("arch/x86_64/gdt.zig");
const idt = @import("arch/x86_64/idt.zig");
const memory_map = @import("mm/memory_map.zig");
const serial = @import("arch/x86_64/serial.zig");
const shared = @import("shared");

var boot_info: *const shared.BootInfo = undefined;

pub fn init(bi: *const shared.BootInfo) void {
    boot_info = bi;

    gdt.init();
    gdt.load();

    idt.init();
    idt.load();

    serial.init();

    serial.writeString("\r\n=== Kernel Entry ===\r\n");

    memory_map.init(bi);
    printMemoryMap();

    const vga: [*]volatile u16 = @ptrFromInt(0xb8000);
    vga[0] = 0x2F4B; // 'K' in green
    vga[1] = 0x2F4F; // 'O'
    vga[2] = 0x2F4B; // 'K'

    serial.writeString("Kernel initialized. Halting.\r\n");
}

fn printMemoryMap() void {
    serial.writeString("\r\n--- Physical Memory Map ---\r\n");
    for (memory_map.regionsSlice()) |region| {
        serial.printf("  [{s}] 0x{x} - 0x{x} ({d} pages)", .{
            region.kind.name(),
            region.start,
            region.end,
            (region.end - region.start) / 4096,
        });

        if (region.boot_reserved) {
            serial.printf("  BOOT:{s}", .{region.reservation.?});
        }

        serial.printf("  alloc={s}\r\n", .{if (region.allocatable) "yes" else "no"});
    }
    serial.printf("Total regions: {d}\r\n", .{memory_map.regionCount()});
}

pub fn run() noreturn {
    while (true) cpu.hlt();
}
