const shared = @import("shared");

/// UEFI memory descriptor core fields (40 bytes). Descriptors may be padded to
/// `descriptor_size` bytes (commonly 48).
pub const UefiDescriptor = extern struct {
    type: u32,
    physical_start: u64,
    virtual_start: u64,
    number_of_pages: u64,
    attribute: u64,
};

pub const UefiMemoryType = enum(u32) {
    reserved = 0,
    loader_code = 1,
    loader_data = 2,
    boot_services_code = 3,
    boot_services_data = 4,
    runtime_services_code = 5,
    runtime_services_data = 6,
    conventional = 7,
    unusable = 8,
    acpi_reclaim = 9,
    acpi_nvs = 10,
    mmio = 11,
    mmio_port = 12,
    pal_code = 13,
    persistent = 14,
    unaccepted = 15,
    _,

    pub fn name(self: UefiMemoryType) []const u8 {
        return switch (self) {
            .reserved => "reserved",
            .loader_code => "loader_code",
            .loader_data => "loader_data",
            .boot_services_code => "boot_services_code",
            .boot_services_data => "boot_services_data",
            .runtime_services_code => "runtime_services_code",
            .runtime_services_data => "runtime_services_data",
            .conventional => "conventional",
            .unusable => "unusable",
            .acpi_reclaim => "acpi_reclaim",
            .acpi_nvs => "acpi_nvs",
            .mmio => "mmio",
            .mmio_port => "mmio_port",
            .pal_code => "pal_code",
            .persistent => "persistent",
            .unaccepted => "unaccepted",
            _ => "unknown",
        };
    }
};

pub const RegionKind = enum {
    conventional,
    reserved,
    loader,
    boot_services,
    runtime,
    mmio,
    acpi,
    unusable,
    unknown,

    pub fn name(self: RegionKind) []const u8 {
        return @tagName(self);
    }
};

pub const Region = struct {
    start: u64,
    end: u64,
    kind: RegionKind,
    uefi_type: u32,
    allocatable: bool,
    boot_reserved: bool = false,
    reservation: ?[]const u8 = null,
};

const max_regions = 256;

var regions: [max_regions]Region = undefined;
var region_count: usize = 0;

extern var _kernel_start: u8;
extern var _kernel_end: u8;

pub fn init(boot_info: *const shared.BootInfo) void {
    loadMap(&boot_info.memory_map);
    reserveBootOwned(boot_info);
}

pub fn loadMap(map: *const shared.MemoryMap) void {
    region_count = 0;
    parseUefiMap(map);
}

pub fn markReserved(start: u64, end: u64, name: []const u8) void {
    for (regions[0..region_count]) |*region| {
        if (!rangesOverlap(region.start, region.end, start, end)) continue;
        region.allocatable = false;
        region.boot_reserved = true;
        region.reservation = name;
    }
}

pub fn regionCount() usize {
    return region_count;
}

pub fn regionsSlice() []const Region {
    return regions[0..region_count];
}

pub fn classifyType(uefi_type: u32) RegionKind {
    return switch (uefi_type) {
        0 => .reserved,
        1, 2 => .loader,
        3, 4 => .boot_services,
        5, 6 => .runtime,
        7 => .conventional,
        8 => .unusable,
        9, 10 => .acpi,
        11, 12 => .mmio,
        else => .unknown,
    };
}

pub fn isAllocatable(kind: RegionKind) bool {
    return kind == .conventional;
}

pub fn parseDescriptor(bytes: []const u8) ?UefiDescriptor {
    if (bytes.len < @sizeOf(UefiDescriptor)) return null;
    return @as(*align(1) const UefiDescriptor, @ptrCast(bytes.ptr)).*;
}

pub fn descriptorToRegion(desc: UefiDescriptor) Region {
    const kind = classifyType(desc.type);
    const page_size: u64 = 4096;
    const start = desc.physical_start;
    const end = start + desc.number_of_pages * page_size;
    return .{
        .start = start,
        .end = end,
        .kind = kind,
        .uefi_type = desc.type,
        .allocatable = isAllocatable(kind),
    };
}

fn parseUefiMap(map: *const shared.MemoryMap) void {
    if (map.descriptor_size < @sizeOf(UefiDescriptor)) return;

    var i: usize = 0;
    while (i < map.count) : (i += 1) {
        if (region_count >= max_regions) break;

        const offset = i * map.descriptor_size;
        if (offset + @sizeOf(UefiDescriptor) > map.size) break;

        const bytes = map.entries[offset..][0..map.descriptor_size];
        const desc = parseDescriptor(bytes) orelse continue;
        regions[region_count] = descriptorToRegion(desc);
        region_count += 1;
    }
}

fn reserveBootOwned(boot_info: *const shared.BootInfo) void {
    const kernel_start = @intFromPtr(&_kernel_start);
    const kernel_end = @intFromPtr(&_kernel_end);
    markReserved(kernel_start, kernel_end, "kernel image");

    const mmap = boot_info.memory_map;
    const mmap_start = @intFromPtr(mmap.entries);
    const mmap_end = mmap_start + mmap.size;
    markReserved(mmap_start, mmap_end, "UEFI memory map buffer");

    const boot_info_addr = @intFromPtr(boot_info);
    const boot_info_end = boot_info_addr + @sizeOf(shared.BootInfo);
    markReserved(boot_info_addr, boot_info_end, "boot info");
}

fn rangesOverlap(a_start: u64, a_end: u64, b_start: u64, b_end: u64) bool {
    return a_start < b_end and b_start < a_end;
}
