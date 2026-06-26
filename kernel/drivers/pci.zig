const address = @import("../mm/address.zig");
const serial = @import("../arch/x86_64/serial.zig");

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

const Rsdp = extern struct {
    signature: [8]u8,
    checksum: u8,
    oem_id: [6]u8,
    revision: u8,
    rsdt_address: u32,
    length: u32,
    xsdt_address: u64,
};

const SdtHeader = extern struct {
    signature: [4]u8,
    length: u32,
    revision: u8,
    checksum: u8,
    oem_id: [6]u8,
    oem_table_id: [8]u8,
    oem_revision: u32,
    creator_id: u32,
    creator_revision: u32,
};

const Mcfg = extern struct {
    header: SdtHeader,
    reserved: u64,
};

const McfgAllocation = extern struct {
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
    device_count = 0;
    use_mcfg = false;
    mcfg_allocs = &.{}; // reset slice

    if (findMcfg(rsdp_virt)) |mcfg| {
        const mcfg_bytes: [*]const u8 = @ptrCast(mcfg);
        const alloc_bytes = mcfg.header.length - @sizeOf(Mcfg);
        const alloc_count = alloc_bytes / @sizeOf(McfgAllocation);
        if (alloc_count > max_mcfg_allocs) return PciError.TooManyDevices;

        var i: usize = 0;
        while (i < alloc_count) : (i += 1) {
            const alloc = @as(*const McfgAllocation, @ptrCast(@alignCast(
                mcfg_bytes + @sizeOf(Mcfg) + i * @sizeOf(McfgAllocation),
            )));
            mcfg_storage[i] = alloc.*;
        }
        if (alloc_count > 0) {
            mcfg_allocs = mcfg_storage[0..alloc_count];
            use_mcfg = true;
        }
    }

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
    outl(config_address_port, config_addr);
    return inl(config_data_port);
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
    outl(config_address_port, config_addr);
    outl(config_data_port, value);
}

pub fn logDevices() void {
    serial.writeString("\r\n--- PCI ---\r\n");
    if (use_mcfg) {
        serial.printf("Config access: MCFG ({d} allocation(s))\r\n", .{mcfg_allocs.len});
    } else {
        serial.writeString("Config access: legacy I/O ports\r\n");
    }
    serial.printf("Devices found: {d}\r\n", .{device_count});

    for (devices()) |dev| {
        serial.printf(
            "  {x:0>2}:{x:0>2}.{d} {x:0>4}:{x:0>4} class {x:0>2}.{x:0>2}\r\n",
            .{
                dev.bus,
                dev.device,
                dev.function,
                dev.vendor_id,
                dev.device_id,
                dev.class_code,
                dev.subclass,
            },
        );
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

fn findMcfg(rsdp_virt: u64) ?*const Mcfg {
    const rsdp = ptrFromVirt(Rsdp, rsdp_virt);
    if (!sigEq8(&rsdp.signature, "RSD PTR ")) return null;

    const root_phys: u64 = if (rsdp.revision >= 2) rsdp.xsdt_address else rsdp.rsdt_address;
    return findTable(root_phys, .{ 'M', 'C', 'F', 'G' });
}

fn findTable(root_phys: u64, signature: [4]u8) ?*const Mcfg {
    const root = ptrFromPhys(SdtHeader, root_phys);
    if (root.length < @sizeOf(SdtHeader)) return null;

    if (sigEq4(&root.signature, .{ 'X', 'S', 'D', 'T' })) {
        const xsdt_bytes: [*]const u8 = @ptrCast(root);
        const entry_bytes = root.length - @sizeOf(SdtHeader);
        const entry_count = entry_bytes / 8;
        var i: usize = 0;
        while (i < entry_count) : (i += 1) {
            const table_phys = @as(*const u64, @ptrCast(@alignCast(xsdt_bytes + @sizeOf(SdtHeader) + i * 8))).*;
            const table = ptrFromPhys(SdtHeader, table_phys);
            if (sigEq4(&table.signature, signature)) {
                return @ptrCast(@alignCast(table));
            }
        }
        return null;
    }

    if (sigEq4(&root.signature, .{ 'R', 'S', 'D', 'T' })) {
        const rsdt_bytes: [*]const u8 = @ptrCast(root);
        const entry_bytes = root.length - @sizeOf(SdtHeader);
        const entry_count = entry_bytes / 4;
        var i: usize = 0;
        while (i < entry_count) : (i += 1) {
            const table_phys = @as(u64, @as(*const u32, @ptrCast(@alignCast(rsdt_bytes + @sizeOf(SdtHeader) + i * 4))).*);
            const table = ptrFromPhys(SdtHeader, table_phys);
            if (sigEq4(&table.signature, signature)) {
                return @ptrCast(@alignCast(table));
            }
        }
        return null;
    }

    return null;
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

fn ptrFromPhys(comptime T: type, phys: u64) *const T {
    return @ptrCast(@alignCast(@as(*const anyopaque, @ptrFromInt(address.physToVirt(phys)))));
}

fn ptrFromVirt(comptime T: type, virt: u64) *const T {
    return @ptrCast(@alignCast(@as(*const anyopaque, @ptrFromInt(virt))));
}

fn sigEq4(sig: *const [4]u8, expected: [4]u8) bool {
    return sig[0] == expected[0] and sig[1] == expected[1] and
        sig[2] == expected[2] and sig[3] == expected[3];
}

fn sigEq8(sig: *const [8]u8, expected: []const u8) bool {
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        if (sig[i] != expected[i]) return false;
    }
    return true;
}

fn outl(port: u16, value: u32) void {
    asm volatile ("outl %[value], %[port]"
        :
        : [value] "{eax}" (value),
          [port] "{dx}" (port),
    );
}

fn inl(port: u16) u32 {
    return asm volatile ("inl %[port], %[result]"
        : [result] "={eax}" (-> u32),
        : [port] "{dx}" (port),
    );
}
