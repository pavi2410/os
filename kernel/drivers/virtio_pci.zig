const paging = @import("../arch/x86_64/paging.zig");
const pci = @import("pci.zig");
const virtual = @import("../mm/virtual.zig");

pub const VirtioError = error{
    NotFound,
    NoCapabilities,
    BadBar,
    MapFailed,
    FeatureNegotiationFailed,
    QueueSetupFailed,
    DeviceFailed,
};

pub const Device = struct {
    pci_addr: pci.Addr,
    common_cfg: u64,
    notify_base: u64,
    notify_multiplier: u32,
    isr_status: u64,
    device_cfg: u64,

    pub fn init(pci_dev: *const pci.Device) VirtioError!Device {
        const addr = pci_dev.addr();
        pci.enableDevice(addr);

        var common_cfg: u64 = 0;
        var notify_base: u64 = 0;
        var notify_multiplier: u32 = 0;
        var isr_status: u64 = 0;
        var device_cfg: u64 = 0;

        var cap_off = pci.readConfig8(addr, 0x34);
        while (cap_off != 0) {
            const cap_id = pci.readConfig8(addr, cap_off);
            const next = pci.readConfig8(addr, cap_off + 1);
            if (cap_id == 0x09) {
                const cfg_type = pci.readConfig8(addr, cap_off + 3);
                const bar = pci.readConfig8(addr, cap_off + 4);
                const bar_off = pci.readConfig32(addr, cap_off + 8);
                const bar_phys = pci.barAddress(addr, bar);
                if (bar_phys == 0 and cfg_type != 5) return VirtioError.BadBar;
                if (bar_phys == 0) continue;

                const bar_virt = virtual.mapMmioPages(bar_phys, 4) catch return VirtioError.MapFailed;

                switch (cfg_type) {
                    1 => common_cfg = bar_virt + bar_off,
                    2 => {
                        notify_base = bar_virt + bar_off;
                        notify_multiplier = pci.readConfig32(addr, cap_off + 16);
                        if (notify_multiplier == 0) notify_multiplier = 4;
                    },
                    3 => isr_status = bar_virt + bar_off,
                    4 => device_cfg = bar_virt + bar_off,
                    5 => {}, // optional PCI config window
                    else => {},
                }
            }
            cap_off = next;
        }

        if (common_cfg == 0 or notify_base == 0) return VirtioError.NoCapabilities;

        return .{
            .pci_addr = addr,
            .common_cfg = common_cfg,
            .notify_base = notify_base,
            .notify_multiplier = notify_multiplier,
            .isr_status = isr_status,
            .device_cfg = device_cfg,
        };
    }

    pub fn reset(self: *const Device) void {
        self.writeStatus(0);
    }

    pub fn acknowledge(self: *const Device) void {
        self.writeStatus(self.readStatus() | 1);
    }

    pub fn setDriver(self: *const Device) void {
        self.writeStatus(self.readStatus() | 2);
    }

    pub fn negotiateFeatures(self: *const Device, driver_features: u64) VirtioError!void {
        self.writeDeviceFeatureSelect(0);
        const dev_lo = self.readDeviceFeature();
        self.writeDeviceFeatureSelect(1);
        const dev_hi = self.readDeviceFeature();
        _ = dev_lo;
        _ = dev_hi;

        self.writeDriverFeatureSelect(0);
        self.writeDriverFeature(@truncate(driver_features));
        self.writeDriverFeatureSelect(1);
        self.writeDriverFeature(@truncate(driver_features >> 32));

        var status = self.readStatus();
        status |= 8; // FEATURES_OK
        self.writeStatus(status);
        if (self.readStatus() & 8 == 0) return VirtioError.FeatureNegotiationFailed;
    }

    pub fn setDriverOk(self: *const Device) void {
        self.writeStatus(self.readStatus() | 4);
    }

    pub fn readStatus(self: *const Device) u8 {
        return self.readCommon8(0x14);
    }

    pub fn writeStatus(self: *const Device, value: u8) void {
        self.writeCommon8(0x14, value);
    }

    pub fn selectQueue(self: *const Device, queue: u16) void {
        self.writeCommon16(0x16, queue);
    }

    pub fn queueSize(self: *const Device) u16 {
        return self.readCommon16(0x18);
    }

    pub fn setupQueue(
        self: *const Device,
        queue: u16,
        desc_phys: u64,
        driver_phys: u64,
        device_phys: u64,
        max_size: u16,
    ) VirtioError!u16 {
        self.selectQueue(queue);
        const size = self.queueSize();
        if (size == 0 or size > max_size) return VirtioError.QueueSetupFailed;

        self.writeCommon64(0x20, desc_phys);
        self.writeCommon64(0x28, driver_phys);
        self.writeCommon64(0x30, device_phys);
        self.writeCommon16(0x1C, 1);
        return size;
    }

    pub fn notifyQueue(self: *const Device, queue: u16) void {
        const off = @as(u64, queue) * self.notify_multiplier;
        const ptr: *volatile u16 = @ptrFromInt(self.notify_base + off);
        ptr.* = queue;
    }

    pub fn ackInterrupt(self: *const Device) void {
        if (self.isr_status == 0) return;
        _ = @as(*volatile u8, @ptrFromInt(self.isr_status)).*;
    }

    pub fn readDevice64(self: *const Device, offset: u32) u64 {
        const lo = self.readDevice32(offset);
        const hi = self.readDevice32(offset + 4);
        return lo | (@as(u64, hi) << 32);
    }

    pub fn readDevice32(self: *const Device, offset: u32) u32 {
        return @as(*const volatile u32, @ptrFromInt(self.device_cfg + offset)).*;
    }

    fn readCommon8(self: *const Device, offset: u32) u8 {
        return @as(*const volatile u8, @ptrFromInt(self.common_cfg + offset)).*;
    }

    fn writeCommon8(self: *const Device, offset: u32, value: u8) void {
        @as(*volatile u8, @ptrFromInt(self.common_cfg + offset)).* = value;
    }

    fn readCommon16(self: *const Device, offset: u32) u16 {
        return @as(*const volatile u16, @ptrFromInt(self.common_cfg + offset)).*;
    }

    fn writeCommon16(self: *const Device, offset: u32, value: u16) void {
        @as(*volatile u16, @ptrFromInt(self.common_cfg + offset)).* = value;
    }

    fn writeCommon64(self: *const Device, offset: u32, value: u64) void {
        @as(*volatile u64, @ptrFromInt(self.common_cfg + offset)).* = value;
    }

    fn writeDeviceFeatureSelect(self: *const Device, sel: u32) void {
        @as(*volatile u32, @ptrFromInt(self.common_cfg + 0x00)).* = sel;
    }

    fn readDeviceFeature(self: *const Device) u32 {
        return @as(*const volatile u32, @ptrFromInt(self.common_cfg + 0x04)).*;
    }

    fn writeDriverFeatureSelect(self: *const Device, sel: u32) void {
        @as(*volatile u32, @ptrFromInt(self.common_cfg + 0x08)).* = sel;
    }

    fn writeDriverFeature(self: *const Device, value: u32) void {
        @as(*volatile u32, @ptrFromInt(self.common_cfg + 0x0C)).* = value;
    }
};

pub fn findBlockDevice() ?*const pci.Device {
    if (pci.findDevice(pci.Vendor.virtio, pci.DeviceId.blk_modern)) |dev| return dev;
    if (pci.findDevice(pci.Vendor.virtio, pci.DeviceId.blk_legacy)) |dev| return dev;
    return null;
}

pub fn physFromVirt(virt: u64) ?u64 {
    const page = virt & ~@as(u64, paging.page_size - 1);
    const off = virt & (paging.page_size - 1);
    const page_phys = paging.getPhys(page) orelse return null;
    return page_phys + off;
}
