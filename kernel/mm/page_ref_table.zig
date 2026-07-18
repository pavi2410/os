const std = @import("std");

pub const page_size: u64 = 4096;

pub const RefError = error{
    InvalidAddress,
    Underflow,
    Overflow,
};

/// Host-testable per-PFN reference counts for user data pages (atomic for SMP).
pub const PageRefTable = struct {
    counts: []u32,
    max_pfn: usize,

    pub fn initFromMaxPfn(counts: []u32, max_pfn: usize) PageRefTable {
        @memset(counts, 0);
        return .{ .counts = counts, .max_pfn = max_pfn };
    }

    pub fn retain(self: *PageRefTable, phys: u64) RefError!void {
        const pfn = try pfnOf(phys, self.max_pfn);
        const prev = @atomicRmw(u32, &self.counts[pfn], .Add, 1, .monotonic);
        if (prev == std.math.maxInt(u32)) {
            _ = @atomicRmw(u32, &self.counts[pfn], .Sub, 1, .monotonic);
            return RefError.Overflow;
        }
    }

    pub fn release(self: *PageRefTable, phys: u64) RefError!bool {
        const pfn = try pfnOf(phys, self.max_pfn);
        const prev = @atomicRmw(u32, &self.counts[pfn], .Sub, 1, .monotonic);
        if (prev == 0) {
            // Undo underflow.
            _ = @atomicRmw(u32, &self.counts[pfn], .Add, 1, .monotonic);
            return RefError.Underflow;
        }
        return prev == 1;
    }

    pub fn count(self: *const PageRefTable, phys: u64) u32 {
        const pfn = pfnOf(phys, self.max_pfn) catch return 0;
        return @atomicLoad(u32, &self.counts[pfn], .monotonic);
    }
};

pub fn pfnOf(phys: u64, max_pfn: usize) RefError!usize {
    if (phys & (page_size - 1) != 0 or phys == 0) return RefError.InvalidAddress;
    const pfn: usize = @intCast(phys / page_size);
    if (pfn > max_pfn) return RefError.InvalidAddress;
    return pfn;
}
