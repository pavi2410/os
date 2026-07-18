const physical = @import("physical.zig");
const core = @import("page_cache_core.zig");
const spinlock = @import("../sync/spinlock.zig");

pub const max_slots = core.max_slots;
pub const CacheError = core.CacheError;
pub const Key = core.Key;
pub const Slot = core.Slot;
pub const PageCache = core.PageCache;

var global_cache: PageCache = .{};
var global_ready: bool = false;
var cache_lock: spinlock.SpinLock = .{};

fn kernelAlloc() CacheError!u64 {
    return physical.allocPage() catch return CacheError.OutOfMemory;
}

fn kernelFree(phys: u64) void {
    physical.freePage(phys) catch {};
}

pub fn init() void {
    global_cache = PageCache.init(kernelAlloc, kernelFree);
    global_ready = true;
}

pub fn global() *PageCache {
    return &global_cache;
}

pub fn ready() bool {
    return global_ready;
}

pub fn lock() void {
    cache_lock.lock();
}

pub fn unlock() void {
    cache_lock.unlock();
}
