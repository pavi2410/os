const kernel = @import("kernel.zig");
const shared = @import("shared");

/// 64 KiB kernel stack in BSS (16-byte aligned).
export var kernel_stack: [64 * 1024]u8 align(16) = undefined;

fn switchToKernelStack() void {
    const stack_top = @intFromPtr(&kernel_stack) + kernel_stack.len;
    asm volatile ("mov %[stack], %%rsp"
        :
        : [stack] "r" (stack_top),
    );
}

/// Kernel entry point — called by the bootloader with boot info in RDI.
export fn _start(boot_info_ptr: *const shared.BootInfo) callconv(.{ .x86_64_sysv = .{} }) noreturn {
    switchToKernelStack();
    kernel.init(boot_info_ptr);
    kernel.run();
}
