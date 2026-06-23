const limine = @import("limine");

pub const RegionKind = enum {
    conventional,
    reserved,
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
    limine_type: u64,
    allocatable: bool,
    boot_reserved: bool = false,
    reservation: ?[]const u8 = null,
};

const max_regions = 256;

var regions: [max_regions]Region = undefined;
var region_count: usize = 0;

pub fn init(response: *const limine.MemmapResponse) void {
    loadMap(response);
}

pub fn loadMap(response: *const limine.MemmapResponse) void {
    region_count = 0;

    const entries = response.entries orelse return;
    var i: usize = 0;
    while (i < response.entry_count) : (i += 1) {
        if (region_count >= max_regions) break;
        const entry_ptr = entries[i] orelse continue;
        regions[region_count] = entryToRegion(entry_ptr.*);
        region_count += 1;
    }

    for (regions[0..region_count]) |*region| {
        if (region.kind == .boot_services or region.kind == .reserved) {
            if (region.limine_type == @intFromEnum(limine.MemmapType.executable_and_modules)) {
                region.allocatable = false;
                region.boot_reserved = true;
                region.reservation = "kernel image";
            }
        }
    }
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

pub fn classifyType(memmap_type: u64) RegionKind {
    const ty: limine.MemmapType = @enumFromInt(memmap_type);
    return switch (ty) {
        .usable => .conventional,
        .reserved, .reserved_mapped => .reserved,
        .bootloader_reclaimable => .boot_services,
        .executable_and_modules => .boot_services,
        .framebuffer => .mmio,
        .acpi_reclaimable, .acpi_nvs => .acpi,
        .bad_memory => .unusable,
        _ => .unknown,
    };
}

pub fn isAllocatable(kind: RegionKind) bool {
    return kind == .conventional;
}

pub fn entryToRegion(entry: limine.MemmapEntry) Region {
    const kind = classifyType(entry.type);
    return .{
        .start = entry.base,
        .end = entry.base + entry.length,
        .kind = kind,
        .limine_type = entry.type,
        .allocatable = isAllocatable(kind),
    };
}

fn rangesOverlap(a_start: u64, a_end: u64, b_start: u64, b_end: u64) bool {
    return a_start < b_end and b_start < a_end;
}
