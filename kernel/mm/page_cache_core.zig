const std = @import("std");

pub const max_slots: usize = 256;

pub const CacheError = error{
    OutOfMemory,
    NotFound,
    Busy,
};

pub const Key = struct {
    file_a: u64 = 0,
    file_b: u64 = 0,
    index: u64 = 0,
    /// `@intFromPtr` of the filesystem `Ops` used for populate/writeback.
    ops_ptr: usize = 0,
    /// Snapshot of OpenFile fields for dirty writeback (not part of equality).
    start_cluster: u32 = 0,
    file_size: u32 = 0,
    attr: u8 = 0,
    loc_cluster: u32 = 0,
    loc_offset: u32 = 0,

    pub fn eql(self: Key, other: Key) bool {
        return self.file_a == other.file_a and self.file_b == other.file_b and
            self.index == other.index and self.ops_ptr == other.ops_ptr;
    }
};

pub const Slot = struct {
    key: Key = .{},
    phys: u64 = 0,
    dirty: bool = false,
    /// False until file contents (or zeros) have been loaded into the frame.
    valid: bool = false,
    pinned: u32 = 0,
    referenced: bool = false,
    used: bool = false,
};

pub const AllocFn = *const fn () CacheError!u64;
pub const FreeFn = *const fn (phys: u64) void;
pub const WritebackFn = *const fn (key: Key, phys: u64) CacheError!void;

/// Fixed-pool page cache with clock eviction.
pub const PageCache = struct {
    slots: [max_slots]Slot = @splat(.{}),
    clock: usize = 0,
    hits: u64 = 0,
    misses: u64 = 0,
    alloc_page: ?AllocFn = null,
    free_page: ?FreeFn = null,
    writeback: ?WritebackFn = null,

    pub fn init(alloc_page: AllocFn, free_page: FreeFn) PageCache {
        return .{
            .alloc_page = alloc_page,
            .free_page = free_page,
        };
    }

    pub fn setWriteback(self: *PageCache, wb: WritebackFn) void {
        self.writeback = wb;
    }

    pub fn lookup(self: *PageCache, key: Key) ?*Slot {
        for (&self.slots) |*slot| {
            if (slot.used and slot.key.eql(key)) {
                slot.referenced = true;
                self.hits += 1;
                return slot;
            }
        }
        self.misses += 1;
        return null;
    }

    pub fn getOrAlloc(self: *PageCache, key: Key) CacheError!*Slot {
        if (self.findSlot(key)) |slot| {
            self.hits += 1;
            slot.referenced = true;
            if (slot.pinned == std.math.maxInt(u32)) return CacheError.Busy;
            slot.pinned += 1;
            return slot;
        }
        self.misses += 1;
        const alloc = self.alloc_page orelse return CacheError.OutOfMemory;
        const phys = try alloc();
        errdefer if (self.free_page) |free| free(phys);

        const slot = try self.insertFresh(key, phys);
        slot.pinned += 1;
        return slot;
    }

    pub fn unpin(self: *PageCache, key: Key) void {
        if (self.findSlot(key)) |slot| {
            if (slot.pinned > 0) slot.pinned -= 1;
        }
    }

    pub fn insert(self: *PageCache, key: Key, phys: u64) CacheError!*Slot {
        if (self.findSlot(key)) |existing| return existing;
        return self.insertFresh(key, phys);
    }

    pub fn markDirty(self: *PageCache, key: Key) CacheError!void {
        const slot = self.findSlot(key) orelse return CacheError.NotFound;
        slot.dirty = true;
        slot.referenced = true;
    }

    pub fn flushKey(self: *PageCache, key: Key) CacheError!void {
        const slot = self.findSlot(key) orelse return;
        try self.writebackSlot(slot);
    }

    pub fn flushFile(self: *PageCache, file_a: u64, file_b: u64, ops_ptr: usize) CacheError!void {
        for (&self.slots) |*slot| {
            if (!slot.used) continue;
            if (slot.key.file_a == file_a and slot.key.file_b == file_b and slot.key.ops_ptr == ops_ptr) {
                try self.writebackSlot(slot);
            }
        }
    }

    pub fn usedCount(self: *const PageCache) usize {
        var n: usize = 0;
        for (self.slots) |slot| {
            if (slot.used) n += 1;
        }
        return n;
    }

    fn insertFresh(self: *PageCache, key: Key, phys: u64) CacheError!*Slot {
        const free_idx = self.findFreeSlot() orelse try self.evictOne();
        const slot = &self.slots[free_idx];
        slot.* = .{
            .key = key,
            .phys = phys,
            .dirty = false,
            .valid = false,
            .pinned = 0,
            .referenced = true,
            .used = true,
        };
        return slot;
    }

    fn findSlot(self: *PageCache, key: Key) ?*Slot {
        for (&self.slots) |*slot| {
            if (slot.used and slot.key.eql(key)) return slot;
        }
        return null;
    }

    fn findFreeSlot(self: *PageCache) ?usize {
        for (self.slots, 0..) |slot, i| {
            if (!slot.used) return i;
        }
        return null;
    }

    fn writebackSlot(self: *PageCache, slot: *Slot) CacheError!void {
        if (!slot.dirty) return;
        if (self.writeback) |wb| {
            try wb(slot.key, slot.phys);
        }
        slot.dirty = false;
    }

    fn evictOne(self: *PageCache) CacheError!usize {
        var scanned: usize = 0;
        while (scanned < max_slots * 2) : (scanned += 1) {
            const idx = self.clock % max_slots;
            self.clock += 1;
            const slot = &self.slots[idx];
            if (!slot.used) return idx;
            if (slot.pinned != 0) continue;
            if (slot.referenced) {
                slot.referenced = false;
                continue;
            }
            try self.writebackSlot(slot);
            if (self.free_page) |free| free(slot.phys);
            slot.* = .{};
            return idx;
        }
        return CacheError.OutOfMemory;
    }
};
