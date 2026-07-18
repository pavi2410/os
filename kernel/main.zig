const cpu = @import("arch/x86_64/cpu.zig");
const freestanding_std = @import("freestanding_std.zig");
const kernel = @import("kernel.zig");
const limine = @import("limine");
const panic_root = @import("panic.zig");

pub const std_options_debug_io = freestanding_std.std_options_debug_io;
pub const std_options = freestanding_std.std_options;
pub const panic = panic_root.handler;

export var limine_requests_start: [4]u64 linksection(".limine_requests_start") = limine.REQUESTS_START_MARKER;

export var limine_base_revision: [3]u64 linksection(".limine_requests") = limine.baseRevisionTag(limine.BASE_REVISION);

export var hhdm_request: limine.HhdmRequest linksection(".limine_requests") = .{};
export var memmap_request: limine.MemmapRequest linksection(".limine_requests") = .{};
export var rsdp_request: limine.RsdpRequest linksection(".limine_requests") = .{};
export var bootloader_info_request: limine.BootloaderInfoRequest linksection(".limine_requests") = .{};
export var mp_request: limine.MpRequest linksection(".limine_requests") = .{};

export var limine_requests_end: [2]u64 linksection(".limine_requests_end") = limine.REQUESTS_END_MARKER;

/// 64 KiB kernel stack in BSS (16-byte aligned).
export var kernel_stack: [64 * 1024]u8 align(16) = undefined;

export fn _start() callconv(.c) noreturn {
    cpu.switchStack(@intFromPtr(&kernel_stack) + kernel_stack.len);

    if (!limine.baseRevisionSupported(&limine_base_revision)) {
        cpu.haltForever();
    }

    const hhdm = hhdm_request.response orelse cpu.haltForever();
    const memmap = memmap_request.response orelse cpu.haltForever();
    const rsdp = rsdp_request.response orelse cpu.haltForever();

    kernel.init(.{
        .hhdm_offset = hhdm.offset,
        .memory_map = memmap,
        .rsdp_virt = rsdp.address,
        .bootloader_info = bootloader_info_request.response,
        .mp = mp_request.response,
    });
    kernel.run();
}
