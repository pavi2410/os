const address = @import("mm/address.zig");
const cpu = @import("arch/x86_64/cpu.zig");
const gdt = @import("arch/x86_64/gdt.zig");
const idt = @import("arch/x86_64/idt.zig");
const limine = @import("limine");
const memory_map = @import("mm/memory_map.zig");
const paging = @import("arch/x86_64/paging.zig");
const serial = @import("arch/x86_64/serial.zig");

/// Deliberately unmapped higher-half address used to verify the page fault handler.
const page_fault_test_addr: u64 = 0xFFFFFFFF90000000;

pub const BootContext = struct {
    hhdm_offset: u64,
    memory_map: *const limine.MemmapResponse,
    bootloader_info: ?*const limine.BootloaderInfoResponse,
};

pub fn init(ctx: BootContext) void {
    address.setHhdmOffset(ctx.hhdm_offset);

    gdt.init();
    gdt.load();

    idt.init();
    idt.load();

    serial.init();

    serial.writeString("\r\n=== Kernel Entry ===\r\n");

    if (ctx.bootloader_info) |info| {
        if (info.name) |name| {
            serial.printf("Bootloader: {s}\r\n", .{name});
        }
        if (info.version) |version| {
            serial.printf("Version: {s}\r\n", .{version});
        }
    }

    memory_map.init(ctx.memory_map);
    printMemoryMap();

    verifyHigherHalfExecution();
    verifyPagingHelpers();
    triggerDeliberatePageFault();
}

fn verifyHigherHalfExecution() void {
    const rip = cpu.readRip();
    serial.printf("RIP: 0x{x} (higher-half: {s})\r\n", .{
        rip,
        if (address.isHigherHalf(rip)) "yes" else "NO",
    });
}

fn verifyPagingHelpers() void {
    serial.printf("CR3: 0x{x}\r\n", .{paging.readCr3()});
    serial.printf("Page fault probe 0x{x} mapped: {s}\r\n", .{
        page_fault_test_addr,
        if (paging.isMapped(page_fault_test_addr)) "yes" else "no",
    });
}

fn triggerDeliberatePageFault() noreturn {
    serial.writeString("Triggering deliberate page fault...\r\n");
    const bad_ptr: *volatile u8 = @ptrFromInt(page_fault_test_addr);
    _ = bad_ptr.*;
    cpu.haltForever();
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
    cpu.haltForever();
}
