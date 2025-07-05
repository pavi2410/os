const std = @import("std");

const uefi = @import("uefi.zig");
const MemoryMapInfo = uefi.MemoryMapInfo;

pub fn kernel_entry(_: MemoryMapInfo) noreturn {
    // here you own the machine
    // you can do page tables next
    // for now, do a halt
    const vga: [*]volatile u16 = @ptrFromInt(0xb8000);
    vga[0] = 0x2F4B; // 'K' in green
    vga[1] = 0x2F4F; // 'O'
    vga[2] = 0x2F4B; // 'K'

    while (true) asm volatile ("hlt");
}
