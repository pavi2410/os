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

    const mem_map = uefi.getMemoryMap() orelse {
        uefi.printf("Failed to get memory map.\r\n", .{});
        while (true) {}
    };

    // Exit boot services
    if (!uefi.exitBootServices(mem_map.map_key)) {
        uefi.printf("Failed to exit boot services.\r\n", .{});
        while (true) {}
    }

    // Jump to kernel entry point
    kernel.kernel_entry(mem_map);
}
