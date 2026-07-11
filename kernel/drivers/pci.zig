const acpi_access = @import("../acpi/access.zig");
const address = @import("../mm/address.zig");
const hal = @import("../hal.zig");
const cpu = @import("../arch/x86_64/cpu.zig");

pub const DeviceId = struct {
    pub const blk_modern: u16 = 0x1042;
    pub const blk_legacy: u16 = 0x1001;
    pub const net_modern: u16 = 0x1041;
    pub const net_legacy: u16 = 0x1000;
};

pub const Vendor = struct {
    pub const virtio: u16 = 0x1AF4;
    pub const intel: u16 = 0x8086;
    pub const qemu: u16 = 0x1234;
};

pub const Class = struct {
    pub const mass_storage: u8 = 0x01;
    pub const network: u8 = 0x02;
};

pub const Device = struct {
    segment: u16,
    bus: u8,
    device: u8,
    function: u8,
    vendor_id: u16,
    device_id: u16,
    class_code: u8,
    subclass: u8,
    prog_if: u8,
    header_type: u8,
    bars: [6]u32,

    pub fn addr(self: Device) Addr {
        return .{
            .segment = self.segment,
            .bus = self.bus,
            .device = self.device,
            .function = self.function,
        };
    }
};

pub const Addr = struct {
    segment: u16 = 0,
    bus: u8,
    device: u8,
    function: u8,
};

pub const PciError = error{
    InvalidRsdp,
    ConfigUnavailable,
    TooManyDevices,
};

const config_address_port: u16 = 0xCF8;
const config_data_port: u16 = 0xCFC;

const mcfg_header_size = acpi_access.sdt_header_size + 8;
const mcfg_alloc_size = 16;

const McfgAllocation = struct {
    base: u64,
    segment: u16,
    start_bus: u8,
    end_bus: u8,
    reserved: u32,
};

const max_devices = 64;
const max_mcfg_allocs = 8;

var device_storage: [max_devices]Device = undefined;
var device_count: usize = 0;
var mcfg_storage: [max_mcfg_allocs]McfgAllocation = undefined;
var mcfg_allocs: []const McfgAllocation = &.{};
var use_mcfg = false;

pub fn init(rsdp_virt: u64) PciError!void {
    _ = rsdp_virt;
    device_count = 0;
    use_mcfg = false;
    mcfg_allocs = &.{}; // reset slice

    try enumerateBuses();
}

pub fn deviceCount() usize {
    return device_count;
}

pub fn devices() []const Device {
    return device_storage[0..device_count];
}

pub fn findDevice(vendor_id: u16, device_id: u16) ?*const Device {
    for (devices()) |*dev| {
        if (dev.vendor_id == vendor_id and dev.device_id == device_id) return dev;
    }
    return null;
}

pub fn findClass(class_code: u8, subclass: u8) ?*const Device {
    for (devices()) |*dev| {
        if (dev.class_code == class_code and dev.subclass == subclass) return dev;
    }
    return null;
}

pub fn readConfig8(addr: Addr, offset: u8) u8 {
    return @truncate(readConfig32(addr, offset & 0xFC) >> (@as(u5, @truncate((offset & 3) * 8))));
}

pub fn readConfig16(addr: Addr, offset: u8) u16 {
    return @truncate(readConfig32(addr, offset & 0xFC) >> (@as(u5, @truncate((offset & 2) * 8))));
}

pub fn readConfig32(addr: Addr, offset: u8) u32 {
    if (use_mcfg) {
        if (mcfgConfigPtr(addr, offset & 0xFC)) |ptr| {
            return @as(*const u32, @ptrCast(@alignCast(ptr))).*;
        }
        return 0xFFFF_FFFF;
    }

    const config_addr = 0x8000_0000 |
        (@as(u32, addr.bus) << 16) |
        (@as(u32, addr.device) << 11) |
        (@as(u32, addr.function) << 8) |
        (@as(u32, offset) & 0xFC);
    cpu.outl(config_address_port, config_addr);
    return cpu.inl(config_data_port);
}

pub fn writeConfig16(addr: Addr, offset: u8, value: u16) void {
    const aligned = offset & 0xFC;
    const shift: u5 = @truncate((offset & 2) * 8);
    const orig = readConfig32(addr, aligned);
    const mask = ~(@as(u32, 0xFFFF) << shift);
    writeConfig32(addr, aligned, (orig & mask) | (@as(u32, value) << shift));
}

pub fn writeConfig8(addr: Addr, offset: u8, value: u8) void {
    const aligned = offset & 0xFC;
    const shift: u5 = @truncate((offset & 3) * 8);
    const orig = readConfig32(addr, aligned);
    const mask = ~(@as(u32, 0xFF) << shift);
    writeConfig32(addr, aligned, (orig & mask) | (@as(u32, value) << shift));
}

pub fn enableDevice(addr: Addr) void {
    const cmd = readConfig16(addr, 0x04);
    writeConfig16(addr, 0x04, cmd | 0x0006);
}

pub fn barAddress(addr: Addr, bar_index: usize) u64 {
    const bar_off: u8 = @intCast(0x10 + bar_index * 4);
    const bar_lo = readConfig32(addr, bar_off);
    if (bar_lo == 0 and bar_index == 0) {
        const bar_hi = readConfig32(addr, bar_off + 4);
        if (bar_hi & 1 == 0 and bar_hi >= 0x1000) return bar_hi & 0xFFFF_FFF0;
    }
    if (bar_lo & 1 != 0) return 0;

    var result: u64 = bar_lo & 0xFFFF_FFF0;
    if ((bar_lo & 0x6) == 0x4) {
        const bar_hi = readConfig32(addr, bar_off + 4);
        result |= @as(u64, bar_hi) << 32;
    }
    return result;
}

pub fn findVendor(vendor_id: u16) ?*const Device {
    for (devices()) |*dev| {
        if (dev.vendor_id == vendor_id) return dev;
    }
    return null;
}

pub fn writeConfig32(addr: Addr, offset: u8, value: u32) void {
    if (use_mcfg) {
        if (mcfgConfigPtr(addr, offset & 0xFC)) |ptr| {
            @as(*u32, @ptrCast(@alignCast(ptr))).* = value;
            return;
        }
        return;
    }

    const config_addr = 0x8000_0000 |
        (@as(u32, addr.bus) << 16) |
        (@as(u32, addr.device) << 11) |
        (@as(u32, addr.function) << 8) |
        (@as(u32, offset) & 0xFC);
    cpu.outl(config_address_port, config_addr);
    cpu.outl(config_data_port, value);
}

pub fn logDevices() void {
    hal.console.println("\n--- PCI ---", .{});
    if (use_mcfg) {
        hal.console.println("Config access: MCFG ({d} allocation(s))", .{mcfg_allocs.len});
    } else {
        hal.console.println("Config access: legacy I/O ports", .{});
    }
    hal.console.println("Devices found: {d}", .{device_count});

    for (devices()) |dev| {
        hal.console.println("  {x:0>2}:{x:0>2}.{d} {x:0>4}:{x:0>4} class {x:0>2}.{x:0>2}", .{
                dev.bus,
                dev.device,
                dev.function,
                dev.vendor_id,
                dev.device_id,
                dev.class_code,
                dev.subclass,
            },);
    }
}

fn enumerateBuses() PciError!void {
    if (use_mcfg) {
        for (mcfg_allocs) |alloc| {
            var bus = alloc.start_bus;
            while (bus <= alloc.end_bus) : (bus += 1) {
                try enumerateBus(alloc.segment, bus);
            }
        }
        return;
    }

    var bus: u8 = 0;
    while (true) {
        try enumerateBus(0, bus);
        if (bus == 255) break;
        bus += 1;
    }
}

fn enumerateBus(segment: u16, bus: u8) PciError!void {
    var device: u8 = 0;
    while (device < 32) : (device += 1) {
        const addr0 = Addr{ .segment = segment, .bus = bus, .device = device, .function = 0 };
        const vendor0 = readConfig16(addr0, 0);
        if (vendor0 == 0xFFFF) continue;

        const header_type = readConfig8(addr0, 0x0E);
        const function_limit: u8 = if ((header_type & 0x80) != 0) 8 else 1;

        var function: u8 = 0;
        while (function < function_limit) : (function += 1) {
            const addr = Addr{ .segment = segment, .bus = bus, .device = device, .function = function };
            const vendor_id = readConfig16(addr, 0);
            if (vendor_id == 0xFFFF) continue;

            if (device_count >= max_devices) return PciError.TooManyDevices;

            var bars: [6]u32 = .{0} ** 6;
            const hdr_type = readConfig8(addr, 0x0E) & 0x7F;
            if (hdr_type == 0) {
                var bar: usize = 0;
                while (bar < 6) : (bar += 1) {
                    bars[bar] = readConfig32(addr, @truncate(0x10 + bar * 4));
                }
            }

            device_storage[device_count] = .{
                .segment = segment,
                .bus = bus,
                .device = device,
                .function = function,
                .vendor_id = vendor_id,
                .device_id = readConfig16(addr, 2),
                .class_code = readConfig8(addr, 0x0B),
                .subclass = readConfig8(addr, 0x0A),
                .prog_if = readConfig8(addr, 0x09),
                .header_type = readConfig8(addr, 0x0E),
                .bars = bars,
            };
            device_count += 1;
        }
    }
}

fn findMcfg(rsdp_virt: u64) ?[*]const u8 {
    const root_phys = acpi_access.rootTablePhys(rsdp_virt) orelse return null;

    const mcfg_phys = acpi_access.findTablePhys(root_phys, .{ 'M', 'C', 'F', 'G' }) orelse return null;
    return acpi_access.physBytes(mcfg_phys);
}

fn mcfgConfigPtr(addr: Addr, offset: u8) ?[*]u8 {
    for (mcfg_allocs) |alloc| {
        if (alloc.segment != addr.segment) continue;
        if (addr.bus < alloc.start_bus or addr.bus > alloc.end_bus) continue;

        const bus_offset = @as(u64, addr.bus - alloc.start_bus) << 20;
        const dev_offset = @as(u64, addr.device) << 15;
        const fn_offset = @as(u64, addr.function) << 12;
        const cfg_phys = alloc.base + bus_offset + dev_offset + fn_offset + offset;
        return @ptrFromInt(address.physToVirt(cfg_phys));
    }
    return null;
}
