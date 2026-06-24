pub const page_size: u64 = 4096;

/// Describes a contiguous physical address range for the bitmap core.
pub const Range = struct {
    start: u64,
    end: u64,
    allocatable: bool,
};

/// Host-testable bitmap page allocator indexed by physical frame number (PFN).
pub const PageBitmap = struct {
    bitmap: []u8,
    max_pfn: usize,
    free_pages: usize,
    total_allocatable: usize,
    hint: usize = 0,

    pub fn initFromRegions(bitmap: []u8, regions: []const Range) PageBitmap {
        @memset(bitmap, 0xFF);

        var highest: u64 = 0;
        for (regions) |region| {
            if (!region.allocatable) continue;
            highest = @max(highest, region.end);
        }
        if (highest == 0) {
            @panic("no allocatable regions");
        }

        const max_pfn = highest / page_size;
        if (max_pfn >= bitmap.len * 8) {
            @panic("physical page bitmap too small");
        }

        var self = PageBitmap{
            .bitmap = bitmap,
            .max_pfn = max_pfn,
            .free_pages = 0,
            .total_allocatable = 0,
            .hint = 0,
        };

        for (regions) |region| {
            if (!region.allocatable) continue;
            self.markRangeFree(region.start, region.end);
        }
        self.total_allocatable = self.free_pages;
        self.hint = 0;
        return self;
    }

    pub fn allocPage(self: *PageBitmap) ?u64 {
        if (self.free_pages == 0) return null;

        var pfn = self.hint;
        while (pfn <= self.max_pfn) : (pfn += 1) {
            if (self.isUsed(pfn)) continue;
            self.setUsed(pfn, true);
            self.free_pages -= 1;
            self.hint = pfn + 1;
            return @as(u64, @intCast(pfn)) * page_size;
        }

        pfn = 0;
        while (pfn < self.hint) : (pfn += 1) {
            if (self.isUsed(pfn)) continue;
            self.setUsed(pfn, true);
            self.free_pages -= 1;
            self.hint = pfn + 1;
            return @as(u64, @intCast(pfn)) * page_size;
        }

        return null;
    }

    pub fn freePage(self: *PageBitmap, phys: u64) error{ InvalidAddress, DoubleFree }!void {
        if (phys & (page_size - 1) != 0) return error.InvalidAddress;
        if (phys == 0) return error.InvalidAddress;

        const pfn: usize = @intCast(phys / page_size);
        if (pfn > self.max_pfn) return error.InvalidAddress;
        if (!self.isUsed(pfn)) return error.DoubleFree;

        self.setUsed(pfn, false);
        self.free_pages += 1;
        if (pfn < self.hint) self.hint = pfn;
    }

    pub fn markRangeUsed(self: *PageBitmap, start: u64, end: u64) void {
        var addr = alignUp(start, page_size);
        const end_aligned = alignDown(end, page_size);
        while (addr < end_aligned) : (addr += page_size) {
            const pfn: usize = @intCast(addr / page_size);
            if (pfn > self.max_pfn) break;
            if (!self.isUsed(pfn)) {
                self.setUsed(pfn, true);
                if (self.free_pages > 0) self.free_pages -= 1;
            }
        }
    }

    pub fn markRangeFree(self: *PageBitmap, start: u64, end: u64) void {
        var addr = alignUp(start, page_size);
        const end_aligned = alignDown(end, page_size);
        while (addr < end_aligned) : (addr += page_size) {
            const pfn: usize = @intCast(addr / page_size);
            if (pfn > self.max_pfn) break;
            if (pfn == 0) {
                addr += page_size;
                continue;
            }
            if (self.isUsed(pfn)) {
                self.setUsed(pfn, false);
                self.free_pages += 1;
            }
        }
    }

    pub fn usedPages(self: *const PageBitmap) usize {
        return self.total_allocatable -| self.free_pages;
    }

    fn isUsed(self: *const PageBitmap, pfn: usize) bool {
        const byte = self.bitmap[pfn / 8];
        const mask: u8 = @as(u8, 1) << @truncate(pfn % 8);
        return byte & mask != 0;
    }

    fn setUsed(self: *PageBitmap, pfn: usize, used: bool) void {
        const bit: u8 = @as(u8, 1) << @truncate(pfn % 8);
        if (used) {
            self.bitmap[pfn / 8] |= bit;
        } else {
            self.bitmap[pfn / 8] &= ~bit;
        }
    }
};

fn alignUp(value: u64, alignment: u64) u64 {
    return (value + alignment - 1) & ~(alignment - 1);
}

fn alignDown(value: u64, alignment: u64) u64 {
    return value & ~(alignment - 1);
}
