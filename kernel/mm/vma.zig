const abi_mman = @import("abi_mman");

pub const page_size: u64 = 4096;
pub const max_vmas: usize = 32;

pub const Prot = abi_mman.Prot;
pub const MapFlags = abi_mman.MapFlags;

pub const Kind = enum {
    none,
    elf,
    heap,
    stack,
    anon,
    file,
};

pub const VmaError = error{
    OutOfSlots,
    Overlap,
    NotFound,
    InvalidRange,
};

pub const FileBacking = struct {
    file_a: u64 = 0,
    file_b: u64 = 0,
    file_offset: u64 = 0,
    start_cluster: u32 = 0,
    file_size: u32 = 0,
    attr: u8 = 0,
    loc_cluster: u32 = 0,
    loc_offset: u32 = 0,
};

pub const Vma = struct {
    base: u64 = 0,
    len: u64 = 0,
    prot: Prot = .{},
    flags: MapFlags = .{},
    kind: Kind = .none,
    file: FileBacking = .{},

    pub fn end(self: Vma) u64 {
        return self.base + self.len;
    }

    pub fn contains(self: Vma, addr: u64) bool {
        return self.kind != .none and addr >= self.base and addr < self.end();
    }

    pub fn overlaps(self: Vma, base: u64, len: u64) bool {
        if (self.kind == .none or len == 0) return false;
        const other_end = base + len;
        return base < self.end() and other_end > self.base;
    }

    pub fn isWritable(self: Vma) bool {
        return self.prot.write;
    }

    pub fn isExecutable(self: Vma) bool {
        return self.prot.exec;
    }

    pub fn isReadable(self: Vma) bool {
        return self.prot.read;
    }
};

/// Fixed-capacity per-process virtual memory area table.
pub const VmaTable = struct {
    slots: [max_vmas]Vma = @splat(.{}),

    pub fn init() VmaTable {
        return .{};
    }

    pub fn clear(self: *VmaTable) void {
        self.* = .{};
    }

    pub fn count(self: *const VmaTable) usize {
        var n: usize = 0;
        for (self.slots) |slot| {
            if (slot.kind != .none) n += 1;
        }
        return n;
    }

    pub fn find(self: *const VmaTable, addr: u64) ?Vma {
        for (self.slots) |slot| {
            if (slot.contains(addr)) return slot;
        }
        return null;
    }

    pub fn findIndex(self: *const VmaTable, addr: u64) ?usize {
        for (self.slots, 0..) |slot, i| {
            if (slot.contains(addr)) return i;
        }
        return null;
    }

    pub fn hasOverlap(self: *const VmaTable, base: u64, len: u64) bool {
        for (self.slots) |slot| {
            if (slot.overlaps(base, len)) return true;
        }
        return false;
    }

    pub fn insert(self: *VmaTable, vma: Vma) VmaError!void {
        if (vma.kind == .none or vma.len == 0) return VmaError.InvalidRange;
        if (vma.base % page_size != 0 or vma.len % page_size != 0) return VmaError.InvalidRange;
        if (self.hasOverlap(vma.base, vma.len)) return VmaError.Overlap;

        for (&self.slots) |*slot| {
            if (slot.kind == .none) {
                slot.* = vma;
                return;
            }
        }
        return VmaError.OutOfSlots;
    }

    /// Remove the VMA containing `addr`, or return NotFound.
    pub fn removeAt(self: *VmaTable, addr: u64) VmaError!Vma {
        const idx = self.findIndex(addr) orelse return VmaError.NotFound;
        const removed = self.slots[idx];
        self.slots[idx] = .{};
        return removed;
    }

    /// Remove or split VMAs overlapping `[base, base+len)`. Returns number of
    /// pages that were covered by removed/trimmed regions (for callers that
    /// unmap present pages). Does not touch page tables.
    pub fn unmapRange(self: *VmaTable, base: u64, len: u64) VmaError!void {
        if (len == 0) return;
        if (base % page_size != 0 or len % page_size != 0) return VmaError.InvalidRange;
        const range_end = base + len;

        var i: usize = 0;
        while (i < max_vmas) : (i += 1) {
            const slot = &self.slots[i];
            if (slot.kind == .none or !slot.overlaps(base, len)) continue;

            const slot_end = slot.end();
            if (base <= slot.base and range_end >= slot_end) {
                slot.* = .{};
                continue;
            }

            if (base <= slot.base and range_end < slot_end) {
                // Trim left: keep [range_end, slot_end).
                const old_base = slot.base;
                if (slot.kind == .file) {
                    slot.file.file_offset += range_end - old_base;
                }
                slot.base = range_end;
                slot.len = slot_end - range_end;
                continue;
            }

            if (base > slot.base and range_end >= slot_end) {
                // Trim right: keep [slot.base, base).
                slot.len = base - slot.base;
                continue;
            }

            if (base > slot.base and range_end < slot_end) {
                // Punch hole: keep left, insert right.
                const right = Vma{
                    .base = range_end,
                    .len = slot_end - range_end,
                    .prot = slot.prot,
                    .flags = slot.flags,
                    .kind = slot.kind,
                    .file = blk: {
                        var f = slot.file;
                        if (slot.kind == .file) {
                            f.file_offset += range_end - slot.base;
                        }
                        break :blk f;
                    },
                };
                slot.len = base - slot.base;
                try self.insert(right);
            }
        }
    }

    /// Change protection on the VMA covering `[base, base+len)`, splitting as needed.
    pub fn setProt(self: *VmaTable, base: u64, len: u64, prot: Prot) VmaError!void {
        if (len == 0) return;
        if (base % page_size != 0 or len % page_size != 0) return VmaError.InvalidRange;
        const range_end = base + len;

        // Collect indices that overlap; process into a temp list of replacements.
        var replacements: [max_vmas]Vma = @splat(.{});
        var rep_count: usize = 0;
        var remove_mask: [max_vmas]bool = @splat(false);

        for (self.slots, 0..) |slot, i| {
            if (slot.kind == .none or !slot.overlaps(base, len)) continue;
            if (base < slot.base or range_end > slot.end()) return VmaError.InvalidRange;

            remove_mask[i] = true;
            const slot_end = slot.end();

            if (base > slot.base) {
                replacements[rep_count] = .{
                    .base = slot.base,
                    .len = base - slot.base,
                    .prot = slot.prot,
                    .flags = slot.flags,
                    .kind = slot.kind,
                    .file = slot.file,
                };
                rep_count += 1;
            }

            var mid_file = slot.file;
            if (slot.kind == .file) {
                mid_file.file_offset += base - slot.base;
            }
            replacements[rep_count] = .{
                .base = base,
                .len = len,
                .prot = prot,
                .flags = slot.flags,
                .kind = slot.kind,
                .file = mid_file,
            };
            rep_count += 1;

            if (range_end < slot_end) {
                var right_file = slot.file;
                if (slot.kind == .file) {
                    right_file.file_offset += range_end - slot.base;
                }
                replacements[rep_count] = .{
                    .base = range_end,
                    .len = slot_end - range_end,
                    .prot = slot.prot,
                    .flags = slot.flags,
                    .kind = slot.kind,
                    .file = right_file,
                };
                rep_count += 1;
            }
        }

        if (rep_count == 0) return VmaError.NotFound;

        for (remove_mask, 0..) |should_remove, i| {
            if (should_remove) self.slots[i] = .{};
        }
        for (replacements[0..rep_count]) |vma| {
            try self.insert(vma);
        }
    }

    pub fn cloneFrom(self: *VmaTable, other: *const VmaTable) void {
        self.* = other.*;
    }

    /// Extend or create a heap VMA covering `[heap_base, new_end)`.
    pub fn setHeapEnd(self: *VmaTable, heap_base: u64, new_end: u64) VmaError!void {
        if (new_end < heap_base) return VmaError.InvalidRange;
        if (heap_base % page_size != 0 or new_end % page_size != 0) return VmaError.InvalidRange;

        for (&self.slots) |*slot| {
            if (slot.kind == .heap) {
                if (new_end == heap_base) {
                    slot.* = .{};
                    return;
                }
                slot.base = heap_base;
                slot.len = new_end - heap_base;
                return;
            }
        }

        if (new_end == heap_base) return;
        try self.insert(.{
            .base = heap_base,
            .len = new_end - heap_base,
            .prot = .{ .read = true, .write = true },
            .flags = .{ .private = true, .anonymous = true },
            .kind = .heap,
        });
    }
};

pub fn protFromElfFlags(writable: bool, executable: bool) Prot {
    return .{
        .read = true,
        .write = writable,
        .exec = executable,
    };
}

pub fn violatesWx(prot: Prot) bool {
    return prot.violatesWx();
}
