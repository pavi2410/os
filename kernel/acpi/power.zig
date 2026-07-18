//! ACPI power-off (S5) and QEMU-friendly shutdown.

const access = @import("access.zig");
const bytes = @import("common/bytes");
const cpu = @import("../arch/x86_64/cpu.zig");
const hal = @import("../hal.zig");

var pm1a_cnt_port: u16 = 0;
var slp_typa: u16 = 5; // Common QEMU/Bochs S5 type
var ready: bool = false;

/// Parse FADT (FACP) for PM1a control block. Best-effort; QEMU fallback remains.
pub fn init(rsdp_virt: u64) void {
    const root = access.rootTablePhys(rsdp_virt) orelse return;
    const fadt_phys = access.findTablePhys(root, .{ 'F', 'A', 'C', 'P' }) orelse return;
    const fadt = access.physBytes(fadt_phys);
    const length = bytes.readU32Le(fadt[0..8], 4);
    if (length < 129) return;

    // FADT: PM1a_CNT_BLK at offset 64 (ACPI 1.0) as u32 I/O port.
    const pm1a = bytes.readU32Le(fadt[0..length], 64);
    if (pm1a != 0 and pm1a <= 0xFFFF) {
        pm1a_cnt_port = @truncate(pm1a);
        ready = true;
        hal.console.println("ACPI PM1a_CNT at port 0x{x}", .{pm1a_cnt_port});
    }
}

/// Power off the machine. Tries ACPI S5 then QEMU isa-debug/legacy ports.
pub fn powerOff() noreturn {
    hal.console.println("ACPI poweroff...", .{});

    if (ready and pm1a_cnt_port != 0) {
        // SLP_TYPx in bits 12:10, SLP_EN bit 13.
        const value: u16 = (@as(u16, slp_typa) << 10) | (1 << 13);
        cpu.outw(pm1a_cnt_port, value);
    }

    // QEMU/Bochs legacy poweroff ports.
    cpu.outw(0x604, 0x2000);
    cpu.outw(0xB004, 0x2000);

    while (true) cpu.hlt();
}
