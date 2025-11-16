const std = @import("std");

const kernel = @import("kernel.zig");
const uefi = @import("uefi.zig");

const banner =
    \\               ,-.    ,.  ,  ,-.      /         
    \\             o    )  / | '| /  /\    /          
    \\ ;-. ,-: . , .   /  '--|  | | / |   /   ,-. ,-. 
    \\ | | | | |/  |  /      |  | \/  /  /    | | `-. 
    \\ |-' `-` '   ' '--'    '  '  `-'  /     `-' `-' 
    \\ '                                              
;

pub fn main() void {
    uefi_bootstrap();

    // should never return
    while (true) {}
}

fn uefi_bootstrap() void {
    uefi.clearScreen();
    uefi.printMultine(banner);
    uefi.printf("UEFI kernel bootstrap starting...\r\n", .{});

    // Get initial memory map for informational purposes
    const initial_mem_map = uefi.getMemoryMap() orelse {
        uefi.printf("Failed to get memory map.\r\n", .{});
        while (true) {}
    };

    uefi.printMemoryMap(initial_mem_map);

    // Exit boot services (this will get a fresh memory map internally)
    const mem_map = uefi.exitBootServices() orelse {
        uefi.printf("Failed to exit boot services.\r\n", .{});
        while (true) {}
    };

    // Jump to kernel entry point with the final memory map
    kernel.kernel_entry(mem_map);
}
