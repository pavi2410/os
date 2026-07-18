//! Kernel-private hardware info layouts used by procfs formatters.
//!
//! These are not a userspace syscall ABI. Field layout is still asserted for
//! stable formatter tests (`test/common/abi_test.zig`, `test/kernel/hw_format_test.zig`).

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

pub const MemKind = enum(u32) {
    conventional = 0,
    reserved = 1,
    boot_services = 2,
    runtime = 3,
    mmio = 4,
    acpi = 5,
    unusable = 6,
    unknown = 7,

    pub fn name(self: MemKind) []const u8 {
        return @tagName(self);
    }
};

pub const MemRegionInfo = extern struct {
    start: u64,
    length: u64,
    kind: MemKind,
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

    assertLayout(MemRegionInfo, .{
        .size = 24,
        .fields = &.{
            .{ .field = "start", .offset = 0 },
            .{ .field = "length", .offset = 8 },
            .{ .field = "kind", .offset = 16 },
        },
    });
    if (@sizeOf(MemKind) != 4) @compileError("MemKind must be u32-sized");
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
