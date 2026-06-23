/// Bindings mirroring [limine-protocol/include/limine.h](https://github.com/Limine-Bootloader/limine-protocol).
pub const BASE_REVISION: u64 = 6;

pub const REQUESTS_START_MARKER: [4]u64 = .{
    0xf6b8f4b39de7d1ae,
    0xfab91a6940fcb9cf,
    0x785c6ed015d3e316,
    0x181e920a7852b9d9,
};

pub const REQUESTS_END_MARKER: [2]u64 = .{
    0xadc0e0531bb10d03,
    0x9572709f31764c62,
};

pub const BASE_REVISION_MAGIC: [2]u64 = .{
    0xf9562b2d5c95a6c8,
    0x6a7b384944536bdc,
};

pub inline fn baseRevisionTag(revision: u64) [3]u64 {
    return .{ BASE_REVISION_MAGIC[0], BASE_REVISION_MAGIC[1], revision };
}

pub inline fn baseRevisionSupported(tag: *const [3]u64) bool {
    return tag[2] == 0;
}

pub inline fn loadedBaseRevisionValid(tag: *const [3]u64) bool {
    return tag[1] != BASE_REVISION_MAGIC[1];
}

pub inline fn loadedBaseRevision(tag: *const [3]u64) u64 {
    return tag[1];
}

fn requestId(a: u64, b: u64) [4]u64 {
    return .{ 0xc7b1dd30df4c8b88, 0x0a82e883a194f07b, a, b };
}

pub const MemmapType = enum(u64) {
    usable = 0,
    reserved = 1,
    acpi_reclaimable = 2,
    acpi_nvs = 3,
    bad_memory = 4,
    bootloader_reclaimable = 5,
    executable_and_modules = 6,
    framebuffer = 7,
    reserved_mapped = 8,
    _,

    pub fn name(self: MemmapType) []const u8 {
        return switch (self) {
            .usable => "usable",
            .reserved => "reserved",
            .acpi_reclaimable => "acpi_reclaimable",
            .acpi_nvs => "acpi_nvs",
            .bad_memory => "bad_memory",
            .bootloader_reclaimable => "bootloader_reclaimable",
            .executable_and_modules => "executable_and_modules",
            .framebuffer => "framebuffer",
            .reserved_mapped => "reserved_mapped",
            _ => "unknown",
        };
    }
};

pub const MemmapEntry = extern struct {
    base: u64,
    length: u64,
    type: u64,
};

pub const MemmapResponse = extern struct {
    revision: u64,
    entry_count: u64,
    entries: ?[*]?*MemmapEntry,
};

pub const MemmapRequest = extern struct {
    id: [4]u64 = requestId(0x67cf3d9d378a806f, 0xe304acdfc50c3c62),
    revision: u64 = 0,
    response: ?*MemmapResponse = null,
};

pub const HhdmResponse = extern struct {
    revision: u64,
    offset: u64,
};

pub const HhdmRequest = extern struct {
    id: [4]u64 = requestId(0x48dcf1cb8ad2b852, 0x63984e959a98244b),
    revision: u64 = 0,
    response: ?*HhdmResponse = null,
};

pub const BootloaderInfoResponse = extern struct {
    revision: u64,
    name: ?[*:0]u8,
    version: ?[*:0]u8,
};

pub const BootloaderInfoRequest = extern struct {
    id: [4]u64 = requestId(0xf55038d8e2a1202f, 0x279426fcf5f59740),
    revision: u64 = 0,
    response: ?*BootloaderInfoResponse = null,
};
