const apic = @import("apic.zig");
const cpu = @import("cpu.zig");

pub const TimerError = error{
    CalibrationFailed,
};

/// LAPIC timer IRQ vector (IRQ0 equivalent on the APIC path).
pub const timer_vector: u8 = apic.irq_vector_base;

/// Target timer interrupt rate.
const target_hz: u32 = 100;

/// PIT input frequency (Hz).
const pit_frequency_hz: u32 = 1193182;

/// Calibrate over this many milliseconds using the PIT.
const calibration_ms: u32 = 10;

var calibrated_ticks_per_irq: u32 = 0;

pub fn init() TimerError!u32 {
    const ticks_per_irq = try calibrateTicksPerIrq();
    calibrated_ticks_per_irq = ticks_per_irq;
    apic.startLapicTimer(timer_vector, ticks_per_irq);
    return ticks_per_irq;
}

/// Start the periodic LAPIC timer on an AP using BSP calibration.
pub fn startOnAp() void {
    if (calibrated_ticks_per_irq == 0) return;
    apic.startLapicTimer(timer_vector, calibrated_ticks_per_irq);
}

pub fn ticksPerIrq() u32 {
    return calibrated_ticks_per_irq;
}

fn calibrateTicksPerIrq() TimerError!u32 {
    const pit_divisor = (pit_frequency_hz * calibration_ms) / 1000;
    if (pit_divisor == 0) return TimerError.CalibrationFailed;

    // Channel 2, lobyte/hibyte, mode 0 (one-shot), binary.
    cpu.outb(0x43, 0b10110000);
    cpu.outb(0x42, @truncate(pit_divisor & 0xFF));
    cpu.outb(0x42, @truncate(pit_divisor >> 8));

    // Pulse channel 2 gate via port 0x61.
    const gate = cpu.inb(0x61);
    cpu.outb(0x61, gate & ~@as(u8, 1));
    cpu.outb(0x61, (gate & ~@as(u8, 1)) | 1);

    apic.prepareLapicTimerCalibration();

    // Wait for PIT channel 2 output (bit 5 of port 0x61).
    while (cpu.inb(0x61) & 0x20 == 0) {}

    const elapsed = 0xFFFF_FFFF - apic.lapicReadTimerCurrentCount();
    if (elapsed == 0) return TimerError.CalibrationFailed;

    const ticks_per_ms = elapsed / calibration_ms;
    if (ticks_per_ms == 0) return TimerError.CalibrationFailed;

    const ticks_per_irq = ticks_per_ms * 1000 / target_hz;
    if (ticks_per_irq == 0) return TimerError.CalibrationFailed;

    return ticks_per_irq;
}
