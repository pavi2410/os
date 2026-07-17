const std = @import("std");
const page_cache = @import("page_cache");

var next_phys: u64 = 0x1000;
var freed: usize = 0;
var writebacks: usize = 0;

fn testAlloc() page_cache.CacheError!u64 {
    const p = next_phys;
    next_phys += 0x1000;
    return p;
}

fn testFree(phys: u64) void {
    _ = phys;
    freed += 1;
}

fn testWriteback(key: page_cache.Key, phys: u64) page_cache.CacheError!void {
    _ = key;
    _ = phys;
    writebacks += 1;
}

fn reset() page_cache.PageCache {
    next_phys = 0x1000;
    freed = 0;
    writebacks = 0;
    var cache = page_cache.PageCache.init(testAlloc, testFree);
    cache.setWriteback(testWriteback);
    return cache;
}

test "hit and miss counters" {
    var cache = reset();
    const key = page_cache.Key{ .file_a = 1, .file_b = 2, .index = 0 };
    const slot = try cache.getOrAlloc(key);
    try std.testing.expectEqual(@as(u64, 1), cache.misses);
    cache.unpin(key);
    _ = slot;

    const again = try cache.getOrAlloc(key);
    try std.testing.expectEqual(@as(u64, 1), cache.hits);
    cache.unpin(key);
    _ = again;
}

test "dirty writeback on flush" {
    var cache = reset();
    const key = page_cache.Key{ .file_a = 1, .file_b = 0, .index = 3 };
    _ = try cache.getOrAlloc(key);
    try cache.markDirty(key);
    cache.unpin(key);
    try cache.flushKey(key);
    try std.testing.expectEqual(@as(usize, 1), writebacks);
}

test "clock eviction frees unpinned pages" {
    var cache = reset();
    var i: u64 = 0;
    while (i < page_cache.max_slots) : (i += 1) {
        const key = page_cache.Key{ .file_a = 1, .file_b = 0, .index = i };
        const slot = try cache.getOrAlloc(key);
        cache.unpin(key);
        _ = slot;
    }
    try std.testing.expectEqual(page_cache.max_slots, cache.usedCount());

    const overflow = page_cache.Key{ .file_a = 1, .file_b = 0, .index = 9999 };
    _ = try cache.getOrAlloc(overflow);
    cache.unpin(overflow);
    try std.testing.expect(freed >= 1);
    try std.testing.expectEqual(page_cache.max_slots, cache.usedCount());
}

test "pinned page is not evicted" {
    var cache = reset();
    const pinned_key = page_cache.Key{ .file_a = 7, .file_b = 0, .index = 0 };
    _ = try cache.getOrAlloc(pinned_key);
    // leave pinned

    var i: u64 = 1;
    while (i < page_cache.max_slots) : (i += 1) {
        const key = page_cache.Key{ .file_a = 7, .file_b = 0, .index = i };
        const slot = try cache.getOrAlloc(key);
        cache.unpin(key);
        _ = slot;
    }

    // Force many evictions; pinned slot must remain.
    var extra: u64 = 0;
    while (extra < 32) : (extra += 1) {
        const key = page_cache.Key{ .file_a = 8, .file_b = 0, .index = extra };
        const slot = try cache.getOrAlloc(key);
        cache.unpin(key);
        _ = slot;
    }

    try std.testing.expect(cache.lookup(pinned_key) != null);
    cache.unpin(pinned_key);
}
