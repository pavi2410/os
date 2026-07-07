pub const PciClass = enum(u8) {
    unclassified = 0x00,
    storage = 0x01,
    network = 0x02,
    display = 0x03,
    bridge = 0x06,
    serial_bus = 0x0C,
};

pub const StorageSubclass = enum(u8) {
    scsi = 0x00,
    ide = 0x01,
    nvme = 0x08,
};

pub fn className(class_code: u8, subclass: u8) []const u8 {
    return switch (class_code) {
        @intFromEnum(PciClass.unclassified) => "Unclassified",
        @intFromEnum(PciClass.storage) => storageSubclassName(subclass),
        @intFromEnum(PciClass.network) => "Network",
        @intFromEnum(PciClass.display) => "Display",
        @intFromEnum(PciClass.bridge) => "Bridge",
        @intFromEnum(PciClass.serial_bus) => "Serial bus",
        else => "Device",
    };
}

fn storageSubclassName(subclass: u8) []const u8 {
    return switch (subclass) {
        @intFromEnum(StorageSubclass.scsi) => "SCSI storage",
        @intFromEnum(StorageSubclass.ide) => "IDE storage",
        @intFromEnum(StorageSubclass.nvme) => "NVMe storage",
        else => "Mass storage",
    };
}
