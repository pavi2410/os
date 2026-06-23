const kernel = @import("kernel.zig");
const shared = @import("shared");

/// Kernel entry point — called by the bootloader with boot info in RDI.
export fn _start(boot_info_ptr: *const shared.BootInfo) callconv(.{ .x86_64_sysv = .{} }) noreturn {
    kernel.init(boot_info_ptr);
    kernel.run();
}
