const address = @import("mm/address.zig");
const apic = @import("arch/x86_64/apic.zig");
const cpu = @import("arch/x86_64/cpu.zig");
const gdt = @import("arch/x86_64/gdt.zig");
const heap = @import("mm/heap.zig");
const idt = @import("arch/x86_64/idt.zig");
const interrupts = @import("arch/x86_64/interrupts.zig");
const timer = @import("arch/x86_64/timer.zig");
const rtc = @import("arch/x86_64/rtc.zig");
const limine = @import("limine");
const memory_map = @import("mm/memory_map.zig");
const paging = @import("arch/x86_64/paging.zig");
const physical = @import("mm/physical.zig");
const hal = @import("hal.zig");
const scheduler = @import("proc/scheduler.zig");
const process = @import("proc/process.zig");
const tty = @import("drivers/tty.zig");
const pci = @import("drivers/pci.zig");
const driver_manager = @import("drivers/manager.zig");
const tap_suite = @import("boot/tap_suite.zig");
const vfs = @import("fs/vfs.zig");
const syscall = @import("syscall/entry.zig");
const thread = @import("proc/thread.zig");
const virtual = @import("mm/virtual.zig");

/// Deliberately unmapped higher-half address used to verify the page fault handler.
const page_fault_test_addr: u64 = 0xFFFFFFFF90000000;

/// Compile-time boot diagnostics. Disable for normal Phase 3 runtime development.
const boot_debug = struct {
    pub const allocator_stress: bool = false;
    pub const page_fault_test: bool = false;
    pub const thread_switch_test: bool = false;
};

pub const BootContext = struct {
    hhdm_offset: u64,
    memory_map: *const limine.MemmapResponse,
    rsdp_virt: u64,
    bootloader_info: ?*const limine.BootloaderInfoResponse,
};

pub fn init(ctx: BootContext) void {
    address.setHhdmOffset(ctx.hhdm_offset);

    gdt.init();
    gdt.load();

    idt.init();
    idt.load();

    hal.console.init();

    hal.console.writeString("\r\n=== Kernel Entry ===\r\n");

    if (ctx.bootloader_info) |info| {
        if (info.name) |name| {
            hal.console.printf("Bootloader: {s}\r\n", .{name});
        }
        if (info.version) |version| {
            hal.console.printf("Version: {s}\r\n", .{version});
        }
    }

    memory_map.init(ctx.memory_map);
    reserveMemoryMapBuffer(ctx.memory_map);
    printMemoryMap();

    verifyHigherHalfExecution();
    verifyPagingHelpers();

    initMemoryAllocators();
    printAllocatorStats();

    if (boot_debug.allocator_stress) {
        runPhysicalStressTest();
        runHeapStressTest();
        verifyMemoryMapBuffer(ctx.memory_map);
        printAllocatorStats();
    }

    hal.console.writeString("\r\n=== Phase 3 runtime ===\r\n");
    syscall.init();
    process.init();
    tty.init();
    initApic(ctx.rsdp_virt);
    initPci(ctx.rsdp_virt);
    initBlock();
    initNetwork();
    initTimer();
    rtc.init();
    initScheduler();

    if (boot_debug.thread_switch_test) {
        thread.runSwitchTest(10_000);
    }

    if (boot_debug.page_fault_test) {
        triggerDeliberatePageFault();
    }
}

fn initNetwork() void {
    if (!driver_manager.initNetwork()) return;
}

fn initBlock() void {
    if (!driver_manager.initBlock()) return;
    initVfs();
}

fn initVfs() void {
    vfs.init() catch {
        hal.console.writeString("VFS init failed\r\n");
        return;
    };
    vfs.logStatus();
}

fn initPci(rsdp_virt: u64) void {
    pci.init(rsdp_virt) catch {
        hal.console.writeString("PCI init failed\r\n");
        return;
    };
    pci.logDevices();
}

fn initApic(rsdp_virt: u64) void {
    hal.console.writeString("\r\n--- APIC ---\r\n");
    apic.init(rsdp_virt) catch |err| {
        hal.console.printf("APIC init failed: {s}\r\n", .{@errorName(err)});
        hal.processor.haltForever();
    };
    hal.console.printf("LAPIC ID: {d}\r\n", .{apic.lapicId()});
    hal.console.printf("IOAPIC count: {d}\r\n", .{apic.ioApicCount()});
    hal.console.writeString("Legacy PIC masked, IOAPIC pins masked\r\n");
}

fn initTimer() void {
    hal.console.writeString("\r\n--- Timer ---\r\n");
    interrupts.registerIrq(timer.timer_vector, interrupts.timerIrqHandler);
    const ticks_per_irq = timer.init() catch {
        hal.console.writeString("LAPIC timer init failed\r\n");
        hal.processor.haltForever();
    };
    hal.console.printf("LAPIC periodic timer started ({d} Hz, {d} ticks/irq)\r\n", .{
        100,
        ticks_per_irq,
    });
}

fn initScheduler() void {
    scheduler.init();
}

fn reserveMemoryMapBuffer(response: *const limine.MemmapResponse) void {
    const response_phys = address.virtToPhys(@intFromPtr(response));
    var reserve_start = response_phys;
    var reserve_end = response_phys + 4096;

    if (response.entries) |entries| {
        var i: usize = 0;
        while (i < response.entry_count) : (i += 1) {
            if (entries[i]) |entry| {
                const entry_phys = address.virtToPhys(@intFromPtr(entry));
                reserve_start = @min(reserve_start, entry_phys);
                reserve_end = @max(reserve_end, entry_phys + @sizeOf(limine.MemmapEntry));
            }
        }
    }

    reserve_start &= ~@as(u64, 4095);
    reserve_end = (reserve_end + 4095) & ~@as(u64, 4095);
    memory_map.markReserved(reserve_start, reserve_end, "memory map buffer");
}

fn initMemoryAllocators() void {
    hal.console.writeString("\r\n--- Memory Allocators ---\r\n");
    physical.init();
    virtual.init();
    heap.init() catch {
        hal.console.writeString("heap init failed\r\n");
        hal.processor.haltForever();
    };
    hal.console.writeString("physical, virtual, and heap allocators initialized\r\n");
}

fn printAllocatorStats() void {
    hal.console.printf("Physical pages: total={d} free={d} used={d}\r\n", .{
        physical.totalPages(),
        physical.freePages(),
        physical.usedPages(),
    });
    hal.console.printf("Kernel mapped pages: {d}\r\n", .{virtual.mappedPages()});
    hal.console.printf("Heap live allocations: {d} bytes={d} allocs={d} frees={d}\r\n", .{
        heap.liveAllocations(),
        heap.liveBytes(),
        heap.totalAllocs(),
        heap.totalFrees(),
    });
}

fn runPhysicalStressTest() void {
    hal.console.writeString("\r\n--- Physical Page Stress ---\r\n");

    const initial_free = physical.freePages();
    var pages: [64]u64 = undefined;
    var allocated: usize = 0;

    var cycle: usize = 0;
    while (cycle < 1000) : (cycle += 1) {
        const batch = @min(pages.len, physical.freePages());
        var i: usize = 0;
        while (i < batch) : (i += 1) {
            pages[i] = physical.allocPage() catch break;
            allocated += 1;
        }

        i = 0;
        while (i < allocated) : (i += 1) {
            physical.freePage(pages[i]) catch {};
        }
        allocated = 0;
    }

    hal.console.printf("Physical stress cycles: {d}\r\n", .{cycle});
    hal.console.printf("Physical free pages after stress: {d} (initial {d})\r\n", .{
        physical.freePages(),
        initial_free,
    });
}

fn runHeapStressTest() void {
    hal.console.writeString("\r\n--- Kernel Heap Stress ---\r\n");

    const sizes = [_]usize{ 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192 };

    var cycle: usize = 0;
    while (cycle < 1000) : (cycle += 1) {
        const size = sizes[cycle % sizes.len];
        const ptr = heap.kmalloc(size) catch break;

        @as([*]u8, @ptrCast(ptr))[0] = @truncate(cycle);
        @as([*]u8, @ptrCast(ptr))[size - 1] = @truncate(cycle >> 8);

        heap.kfree(ptr) catch break;
    }

    hal.console.printf("Heap stress cycles: {d}\r\n", .{cycle});
    hal.console.printf("Heap counters: live={d} allocs={d} frees={d}\r\n", .{
        heap.liveAllocations(),
        heap.totalAllocs(),
        heap.totalFrees(),
    });
}

fn verifyMemoryMapBuffer(response: *const limine.MemmapResponse) void {
    hal.console.writeString("\r\n--- Memory Map Buffer Check ---\r\n");
    hal.console.printf("Memory map entries still readable: {d}\r\n", .{response.entry_count});

    if (response.entries) |entries| {
        var i: usize = 0;
        while (i < response.entry_count and i < 3) : (i += 1) {
            if (entries[i]) |entry| {
                hal.console.printf("  entry {d}: base=0x{x} len=0x{x}\r\n", .{
                    i,
                    entry.base,
                    entry.length,
                });
            }
        }
    }
}

fn verifyHigherHalfExecution() void {
    const rip = cpu.readRip();
    hal.console.printf("RIP: 0x{x} (higher-half: {s})\r\n", .{
        rip,
        if (address.isHigherHalf(rip)) "yes" else "NO",
    });
}

fn verifyPagingHelpers() void {
    hal.console.printf("CR3: 0x{x}\r\n", .{paging.readCr3()});
    hal.console.printf("Page fault probe 0x{x} mapped: {s}\r\n", .{
        page_fault_test_addr,
        if (paging.isMapped(page_fault_test_addr)) "yes" else "no",
    });
}

fn triggerDeliberatePageFault() noreturn {
    hal.console.writeString("Triggering deliberate page fault...\r\n");
    const bad_ptr: *volatile u8 = @ptrFromInt(page_fault_test_addr);
    _ = bad_ptr.*;
    hal.processor.haltForever();
}

fn printMemoryMap() void {
    hal.console.writeString("\r\n--- Physical Memory Map ---\r\n");
    for (memory_map.regionsSlice()) |region| {
        hal.console.printf("  [{s}] 0x{x} - 0x{x} ({d} pages)", .{
            region.kind.name(),
            region.start,
            region.end,
            (region.end - region.start) / 4096,
        });

        if (region.boot_reserved) {
            hal.console.printf("  BOOT:{s}", .{region.reservation.?});
        }

        hal.console.printf("  alloc={s}\r\n", .{if (region.allocatable) "yes" else "no"});
    }
    hal.console.printf("Total regions: {d}\r\n", .{memory_map.regionCount()});
}

pub fn run() noreturn {
    tap_suite.run();
    scheduler.start();
}
