pub const Error = error{
    NotReady,
    IoError,
    Timeout,
};

pub const Device = struct {
    name: []const u8,
    sector_size: usize,
    capacity_sectors: u64,
    ctx: ?*anyopaque = null,
    is_ready: *const fn (?*anyopaque) bool,
    read_sectors: *const fn (?*anyopaque, lba: u64, buf: []u8) Error!void,
    write_sectors: *const fn (?*anyopaque, lba: u64, buf: []const u8) Error!void,

    pub fn isReady(self: *const Device) bool {
        return self.is_ready(self.ctx);
    }

    pub fn sectorSize(self: *const Device) usize {
        return self.sector_size;
    }

    pub fn capacity(self: *const Device) u64 {
        return self.capacity_sectors;
    }

    pub fn readSectors(self: *const Device, lba: u64, buf: []u8) Error!void {
        try self.read_sectors(self.ctx, lba, buf);
    }

    pub fn writeSectors(self: *const Device, lba: u64, buf: []const u8) Error!void {
        try self.write_sectors(self.ctx, lba, buf);
    }
};

var default_device: ?Device = null;

pub fn registerDefault(device: Device) void {
    default_device = device;
}

pub fn default() ?*const Device {
    if (default_device) |*device| return device;
    return null;
}

pub fn clearDefaultForTest() void {
    default_device = null;
}
