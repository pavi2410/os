const std = @import("std");

pub const page_size: u64 = 4096;

pub const RefError = error{
    InvalidAddress,
    Underflow,
    Overflow,
};

/// Host-testable per-PFN reference counts for user data pages.
pub const PageRefTable = struct {
    counts: []u32,
    max_pfn: usize,

    pub fn initFromMaxPfn(counts: []u32, max_pfn: usize) PageRefTable {
        @memset(counts, 0);
        return .{ .counts = counts, .max_pfn = max_pfn };
    }

    pub fn retain(self: *PageRefTable, phys: u64) RefError!void {
        const pfn = try pfnOf(phys, self.max_pfn);
        if (self.counts[pfn] == std.math.maxInt(u32)) return RefError.Overflow;
        self.counts[pfn] += 1;
    }

    pub fn release(self: *PageRefTable, phys: u64) RefError!bool {
        const pfn = try pfnOf(phys, self.max_pfn);
        if (self.counts[pfn] == 0) return RefError.Underflow;
        self.counts[pfn] -= 1;
        return self.counts[pfn] == 0;
    }

    pub fn count(self: *const PageRefTable, phys: u64) u32 {
        const pfn = pfnOf(phys, self.max_pfn) catch return 0;
        return self.counts[pfn];
    }
};

pub fn pfnOf(phys: u64, max_pfn: usize) RefError!usize {
    if (phys & (page_size - 1) != 0 or phys == 0) return RefError.InvalidAddress;
    const pfn: usize = @intCast(phys / page_size);
    if (pfn > max_pfn) return RefError.InvalidAddress;
    return pfn;
}
