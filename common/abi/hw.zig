//! Hardware snapshot layouts shared by kernel syscall handlers and userspace libc.
//!
//! Use `extern struct` so field order and padding match the C ABI on x86_64.
//! Fixed-size `[N]u8` name buffers are placed before integers so later scalar
//! writes cannot clobber string data during incremental fills.
//!
//! Validate with `zig build test` (`test/common/abi_test.zig`).

const std = @import("std");

pub const CpuInfo = extern struct {
    vendor: [16]u8,
    brand: [64]u8,
    logical_cpus: u32,
    ioapic_count: u32,
    family: u8,
    model: u8,
    stepping: u8,
    apic_id: u8,
};

pub const PciDeviceInfo = extern struct {
    vendor_id: u16,
    device_id: u16,
    segment: u16,
    bus: u8,
    device: u8,
    function: u8,
    class_code: u8,
    subclass: u8,
    prog_if: u8,
    _pad: u8,
};

pub const BlockDeviceInfo = extern struct {
    name: [16]u8,
    sector_size: u32,
    capacity_sectors: u64,
};

pub const MEM_CONVENTIONAL: u32 = 0;
pub const MEM_RESERVED: u32 = 1;
pub const MEM_BOOT_SERVICES: u32 = 2;
pub const MEM_RUNTIME: u32 = 3;
pub const MEM_MMIO: u32 = 4;
pub const MEM_ACPI: u32 = 5;
pub const MEM_UNUSABLE: u32 = 6;
pub const MEM_UNKNOWN: u32 = 7;

pub const MemRegionInfo = extern struct {
    start: u64,
    length: u64,
    kind: u32,
};

comptime {
    assertLayout(CpuInfo, .{
        .size = 92,
        .fields = &.{
            .{ .field = "vendor", .offset = 0 },
            .{ .field = "brand", .offset = 16 },
            .{ .field = "logical_cpus", .offset = 80 },
            .{ .field = "ioapic_count", .offset = 84 },
            .{ .field = "family", .offset = 88 },
            .{ .field = "apic_id", .offset = 91 },
        },
    });

    assertLayout(BlockDeviceInfo, .{
        .size = 32,
        .fields = &.{
            .{ .field = "name", .offset = 0 },
            .{ .field = "sector_size", .offset = 16 },
            .{ .field = "capacity_sectors", .offset = 24 },
        },
    });

    assertLayout(PciDeviceInfo, .{
        .size = 14,
        .fields = &.{
            .{ .field = "vendor_id", .offset = 0 },
            .{ .field = "_pad", .offset = 12 },
        },
    });

    assertLayout(MemRegionInfo, .{
        .size = 24,
        .fields = &.{
            .{ .field = "start", .offset = 0 },
            .{ .field = "length", .offset = 8 },
            .{ .field = "kind", .offset = 16 },
        },
    });
}

const LayoutField = struct {
    field: []const u8,
    offset: usize,
};

const LayoutSpec = struct {
    size: usize,
    fields: []const LayoutField,
};

fn assertLayout(comptime T: type, spec: LayoutSpec) void {
    std.debug.assert(@sizeOf(T) == spec.size);
    inline for (spec.fields) |entry| {
        std.debug.assert(@offsetOf(T, entry.field) == entry.offset);
    }
}
