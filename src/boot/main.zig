const std = @import("std");

const uefi = @import("uefi.zig");
const elf_loader = @import("elf_loader.zig");
const shared = @import("shared");

const W = std.unicode.utf8ToUtf16LeStringLiteral;

const banner =
    \\               ,-.    ,.  ,  ,-.      /
    \\             o    )  / | '| /  /\    /
    \\ ;-. ,-: . , .   /  '--|  | | / |   /   ,-. ,-.
    \\ | | | | |/  |  /      |  | \/  /  /    | | `-.
    \\ |-' `-` '   ' '--'    '  '  `-'  /     `-' `-'
    \\ '
;

pub fn main() void {
    uefi.clearScreen();
    uefi.printMultine(banner);
    uefi.printf("UEFI Bootloader starting...\r\n", .{});

    // Get initial memory map for informational purposes
    const initial_mem_map = uefi.getMemoryMap() orelse {
        uefi.printf("Failed to get memory map.\r\n", .{});
        while (true) {}
    };

    uefi.printMemoryMap(initial_mem_map);

    // Load the kernel ELF file
    uefi.printf("\r\nLoading kernel...\r\n", .{});
    const loaded_kernel = elf_loader.loadKernel(W("kernel.elf")) catch |err| {
        uefi.printf("Failed to load kernel: {any}\r\n", .{err});
        while (true) {}
    };

    uefi.printf("Kernel entry point: 0x{x}\r\n", .{loaded_kernel.entry_point});

    // Exit boot services and get final memory map
    uefi.printf("\r\nExiting boot services...\r\n", .{});
    const final_mem_map = uefi.exitBootServices() orelse {
        uefi.printf("Failed to exit boot services.\r\n", .{});
        while (true) {}
    };

    // Prepare boot info structure
    var boot_info_data = shared.BootInfo{
        .memory_map = .{
            .entries = final_mem_map.mmap_ptr,
            .size = final_mem_map.mmap_size,
            .descriptor_size = final_mem_map.desc_size,
            .descriptor_version = final_mem_map.desc_version,
            .count = final_mem_map.desc_count,
        },
    };

    // Jump to kernel entry point
    // Pass boot info pointer in RDI (System V ABI calling convention)
    const kernel_entry: *const fn (*const shared.BootInfo) callconv(.{ .x86_64_sysv = .{} }) noreturn = @ptrFromInt(loaded_kernel.entry_point);
    kernel_entry(&boot_info_data);
}
