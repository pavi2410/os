const acpi_madt = @import("../../acpi/madt.zig");
const cpu = @import("cpu.zig");
const virtual = @import("../../mm/virtual.zig");

pub const ApicError = error{
    MadtParseFailed,
    NoIoApic,
    GsiNotFound,
    MmioMapFailed,
};

/// First external IRQ vector (IRQ0 -> vector 32).
pub const irq_vector_base: u8 = 32;

const IA32_APIC_BASE: u32 = 0x1B;

const lapic_reg = struct {
    pub const id: u32 = 0x20;
    pub const version: u32 = 0x30;
    pub const tpr: u32 = 0x80;
    pub const eoi: u32 = 0xB0;
    pub const spurious: u32 = 0xF0;
    pub const lvt_timer: u32 = 0x320;
    pub const timer_init_count: u32 = 0x380;
    pub const timer_current_count: u32 = 0x390;
    pub const timer_divide: u32 = 0x3E0;
};

const lapic_timer_divide: u32 = 0x3;
const lvt_timer_masked: u32 = 1 << 16;
const lvt_timer_periodic: u32 = 1 << 17;
const lvt_timer_one_shot: u32 = 0;

const ioapic_reg = struct {
    pub const index: u32 = 0x00;
    pub const data: u32 = 0x10;
    pub const redirection_base: u32 = 0x10;
};

const IoApicState = struct {
    gsi_base: u32,
    virt: u64,
};

const max_ioapics = 8;
var lapic_mmio: u64 = 0;
var boot_lapic_id: u8 = 0;
var ioapics: [max_ioapics]IoApicState = undefined;
var ioapic_count: usize = 0;

pub fn init(rsdp_virt: u64) ApicError!void {
    disableLegacyPic();

    const madt = acpi_madt.parse(rsdp_virt) catch return ApicError.MadtParseFailed;
    if (madt.ioapics.len == 0) return ApicError.NoIoApic;

    try enableLocalApic(madt.local_apic_address);
    boot_lapic_id = lapicId();

    ioapic_count = 0;
    for (madt.ioapics) |ioapic| {
        ioapics[ioapic_count] = .{
            .gsi_base = ioapic.gsi_base,
            .virt = try mapMmio(ioapic.address),
        };
        maskAllPins(ioapic_count);
        ioapic_count += 1;
    }
}

pub fn lapicId() u8 {
    return @truncate(lapicRead(lapic_reg.id) >> 24);
}

pub fn bootLapicId() u8 {
    return boot_lapic_id;
}

pub fn ioApicCount() usize {
    return ioapic_count;
}

pub fn maskGsi(gsi: u32) ApicError!void {
    const loc = findGsi(gsi) orelse return ApicError.GsiNotFound;
    const low = ioapicRead(loc.index, redirectionLowReg(loc.pin));
    ioapicWrite(loc.index, redirectionLowReg(loc.pin), low | (1 << 16));
}

pub fn unmaskGsi(gsi: u32, vector: u8) ApicError!void {
    const loc = findGsi(gsi) orelse return ApicError.GsiNotFound;
    const low = (ioapicRead(loc.index, redirectionLowReg(loc.pin)) & ~@as(u32, 0x1FF)) | vector;
    const high = (ioapicRead(loc.index, redirectionHighReg(loc.pin)) & ~@as(u32, 0xFF000000)) |
        (@as(u32, boot_lapic_id) << 24);
    ioapicWrite(loc.index, redirectionLowReg(loc.pin), low & ~(1 << 16));
    ioapicWrite(loc.index, redirectionHighReg(loc.pin), high);
}

pub fn lapicEoi() void {
    lapicWrite(lapic_reg.eoi, 0);
}

pub fn lapicWriteTimerInitCount(count: u32) void {
    lapicWrite(lapic_reg.timer_init_count, count);
}

pub fn lapicReadTimerCurrentCount() u32 {
    return lapicRead(lapic_reg.timer_current_count);
}

pub fn prepareLapicTimerCalibration() void {
    lapicWrite(lapic_reg.timer_divide, lapic_timer_divide);
    lapicWrite(lapic_reg.lvt_timer, lvt_timer_one_shot | lvt_timer_masked);
    lapicWrite(lapic_reg.timer_init_count, 0xFFFF_FFFF);
}

pub fn startLapicTimer(vector: u8, ticks_per_irq: u32) void {
    lapicWrite(lapic_reg.timer_divide, lapic_timer_divide);
    lapicWrite(lapic_reg.lvt_timer, @as(u32, vector) | lvt_timer_periodic);
    lapicWrite(lapic_reg.timer_init_count, ticks_per_irq);
}

fn mapMmio(phys: u64) ApicError!u64 {
    return virtual.mapMmio(phys) catch ApicError.MmioMapFailed;
}

fn disableLegacyPic() void {
    cpu.outb(0x21, 0xFF);
    cpu.outb(0xA1, 0xFF);
}

fn enableLocalApic(local_apic_address: u64) ApicError!void {
    var msr = cpu.rdmsr(IA32_APIC_BASE);
    msr &= ~@as(u64, 1 << 10); // xAPIC MMIO mode (not x2APIC MSRs)
    msr |= 1 << 11; // global APIC enable
    cpu.wrmsr(IA32_APIC_BASE, msr);

    const lapic_phys = if (local_apic_address != 0)
        local_apic_address
    else
        msr & 0xFFFF_F000;
    lapic_mmio = try mapMmio(lapic_phys);

    lapicWrite(lapic_reg.spurious, 0x1FF);
    lapicWrite(lapic_reg.tpr, 0);
}

fn maskAllPins(ioapic_index: usize) void {
    var pin: u32 = 0;
    while (pin < 24) : (pin += 1) {
        const low = ioapicRead(ioapic_index, redirectionLowReg(pin));
        ioapicWrite(ioapic_index, redirectionLowReg(pin), low | (1 << 16));
    }
}

const GsiLocation = struct {
    index: usize,
    pin: u32,
};

fn findGsi(gsi: u32) ?GsiLocation {
    var i: usize = 0;
    while (i < ioapic_count) : (i += 1) {
        const ioapic = ioapics[i];
        const end = ioapic.gsi_base + 24;
        if (gsi >= ioapic.gsi_base and gsi < end) {
            return .{
                .index = i,
                .pin = gsi - ioapic.gsi_base,
            };
        }
    }
    return null;
}

fn redirectionLowReg(pin: u32) u32 {
    return ioapic_reg.redirection_base + pin * 2;
}

fn redirectionHighReg(pin: u32) u32 {
    return ioapic_reg.redirection_base + pin * 2 + 1;
}

fn lapicRead(reg: u32) u32 {
    const ptr: *const u32 = @ptrFromInt(lapic_mmio + reg);
    return ptr.*;
}

fn lapicWrite(reg: u32, value: u32) void {
    const ptr: *volatile u32 = @ptrFromInt(lapic_mmio + reg);
    ptr.* = value;
}

fn ioapicWrite(ioapic_index: usize, reg: u32, value: u32) void {
    const base = ioapics[ioapic_index].virt;
    const index_ptr: *volatile u32 = @ptrFromInt(base + ioapic_reg.index);
    const data_ptr: *volatile u32 = @ptrFromInt(base + ioapic_reg.data);
    index_ptr.* = reg;
    data_ptr.* = value;
}

fn ioapicRead(ioapic_index: usize, reg: u32) u32 {
    const base = ioapics[ioapic_index].virt;
    const index_ptr: *volatile u32 = @ptrFromInt(base + ioapic_reg.index);
    const data_ptr: *volatile u32 = @ptrFromInt(base + ioapic_reg.data);
    index_ptr.* = reg;
    return data_ptr.*;
}
