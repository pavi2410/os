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
const page_ref = @import("mm/page_ref.zig");
const physical = @import("mm/physical.zig");
const hal = @import("hal.zig");
const scheduler = @import("proc/scheduler.zig");
const process = @import("proc/process.zig");
const tty = @import("drivers/tty.zig");
const pipe = @import("ipc/pipe.zig");
const pci = @import("drivers/pci.zig");
const driver_manager = @import("drivers/manager.zig");
const tap_suite = @import("boot/tap_suite.zig");
const vfs = @import("fs/vfs.zig");
const syscall = @import("syscall/entry.zig");
const user_access = @import("syscall/user_access.zig");
const thread = @import("proc/thread.zig");
const virtual = @import("mm/virtual.zig");
const memory = @import("mm/memory.zig");
const runtime_mod = @import("runtime.zig");

var runtime: runtime_mod.Runtime = .{};

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
    runtime.install();
    address.setHhdmOffset(ctx.hhdm_offset);

    gdt.init();
    gdt.load();

    idt.init();
    idt.load();

    hal.console.init();

    hal.console.println("\n=== Kernel Entry ===", .{});

    if (ctx.bootloader_info) |info| {
        if (info.name) |name| {
            hal.console.println("Bootloader: {s}", .{name});
        }
        if (info.version) |version| {
            hal.console.println("Version: {s}", .{version});
        }
    }

    memory_map.init(ctx.memory_map);
    reserveMemoryMapBuffer(ctx.memory_map);
    printMemoryMap();

    verifyHigherHalfExecution();
    verifyPagingHelpers();
    paging.initKernelAddressSpace(paging.readCr3());

    initMemoryAllocators();
    printAllocatorStats();

    if (boot_debug.allocator_stress) {
        runPhysicalStressTest();
        runHeapStressTest();
        verifyMemoryMapBuffer(ctx.memory_map);
        printAllocatorStats();
    }

    hal.console.println("\n=== Phase 3 runtime ===", .{});
    syscall.init();
    process.init();
    user_access.init();
    tty.init();
    pipe.init();
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
        hal.console.println("VFS init failed", .{});
        return;
    };
    vfs.logStatus();
}

fn initPci(rsdp_virt: u64) void {
    pci.init(rsdp_virt) catch {
        hal.console.println("PCI init failed", .{});
        return;
    };
    pci.logDevices();
}

fn initApic(rsdp_virt: u64) void {
    hal.console.println("\n--- APIC ---", .{});
    apic.init(rsdp_virt) catch |err| {
        hal.console.println("APIC init failed: {s}", .{@errorName(err)});
        hal.processor.haltForever();
    };
    hal.console.println("LAPIC ID: {d}", .{apic.lapicId()});
    hal.console.println("IOAPIC count: {d}", .{apic.ioApicCount()});
    hal.console.println("Legacy PIC masked, IOAPIC pins masked", .{});
}

fn initTimer() void {
    hal.console.println("\n--- Timer ---", .{});
    interrupts.registerIrq(timer.timer_vector, interrupts.timerIrqHandler);
    const ticks_per_irq = timer.init() catch {
        hal.console.println("LAPIC timer init failed", .{});
        hal.processor.haltForever();
    };
    hal.console.println("LAPIC periodic timer started ({d} Hz, {d} ticks/irq)", .{
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
    hal.console.println("\n--- Memory Allocators ---", .{});
    runtime.memory.init() catch {
        hal.console.println("memory service init failed", .{});
        hal.processor.haltForever();
    };
    hal.console.println("physical, virtual, and heap allocators initialized", .{});
}

fn printAllocatorStats() void {
    hal.console.println("Physical pages: total={d} free={d} used={d}", .{
        physical.totalPages(),
        physical.freePages(),
        physical.usedPages(),
    });
    hal.console.println("Kernel mapped pages: {d}", .{virtual.mappedPages()});
    hal.console.println("Heap live allocations: {d} bytes={d} allocs={d} frees={d}", .{
        heap.liveAllocations(),
        heap.liveBytes(),
        heap.totalAllocs(),
        heap.totalFrees(),
    });
}

fn runPhysicalStressTest() void {
    hal.console.println("\n--- Physical Page Stress ---", .{});

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

    hal.console.println("Physical stress cycles: {d}", .{cycle});
    hal.console.println("Physical free pages after stress: {d} (initial {d})", .{
        physical.freePages(),
        initial_free,
    });
}

fn runHeapStressTest() void {
    hal.console.println("\n--- Kernel Heap Stress ---", .{});

    const sizes = [_]usize{ 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192 };

    var cycle: usize = 0;
    while (cycle < 1000) : (cycle += 1) {
        const size = sizes[cycle % sizes.len];
        const ptr = heap.kmalloc(size) catch break;

        @as([*]u8, @ptrCast(ptr))[0] = @truncate(cycle);
        @as([*]u8, @ptrCast(ptr))[size - 1] = @truncate(cycle >> 8);

        heap.kfree(ptr) catch break;
    }

    hal.console.println("Heap stress cycles: {d}", .{cycle});
    hal.console.println("Heap counters: live={d} allocs={d} frees={d}", .{
        heap.liveAllocations(),
        heap.totalAllocs(),
        heap.totalFrees(),
    });
}

fn verifyMemoryMapBuffer(response: *const limine.MemmapResponse) void {
    hal.console.println("\n--- Memory Map Buffer Check ---", .{});
    hal.console.println("Memory map entries still readable: {d}", .{response.entry_count});

    if (response.entries) |entries| {
        var i: usize = 0;
        while (i < response.entry_count and i < 3) : (i += 1) {
            if (entries[i]) |entry| {
                hal.console.println("  entry {d}: base=0x{x} len=0x{x}", .{
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
    hal.console.println("RIP: 0x{x} (higher-half: {s})", .{
        rip,
        if (address.isHigherHalf(rip)) "yes" else "NO",
    });
}

fn verifyPagingHelpers() void {
    hal.console.println("CR3: 0x{x}", .{paging.readCr3()});
    hal.console.println("Page fault probe 0x{x} mapped: {s}", .{
        page_fault_test_addr,
        if (paging.isMapped(page_fault_test_addr)) "yes" else "no",
    });
}

fn triggerDeliberatePageFault() noreturn {
    hal.console.println("Triggering deliberate page fault...", .{});
    const bad_ptr: *volatile u8 = @ptrFromInt(page_fault_test_addr);
    _ = bad_ptr.*;
    hal.processor.haltForever();
}

fn printMemoryMap() void {
    hal.console.println("\n--- Physical Memory Map ---", .{});
    for (memory_map.regionsSlice()) |region| {
        hal.console.print("  [{s}] 0x{x} - 0x{x} ({d} pages)", .{
            region.kind.name(),
            region.start,
            region.end,
            (region.end - region.start) / 4096,
        });

        if (region.boot_reserved) {
            hal.console.print("  BOOT:{s}", .{region.reservation.?});
        }

        hal.console.println("  alloc={s}", .{if (region.allocatable) "yes" else "no"});
    }
    hal.console.println("Total regions: {d}", .{memory_map.regionCount()});
}

pub fn run() noreturn {
    tap_suite.run();
    scheduler.start();
}
