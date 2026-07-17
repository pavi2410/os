const address = @import("../mm/address.zig");
const filesystem = @import("filesystem.zig");
const page_cache = @import("../mm/page_cache.zig");
const paging = @import("../arch/x86_64/paging.zig");

const page_size = paging.page_size;

var bound_ops: ?*const filesystem.Ops = null;

fn keyFor(file: filesystem.OpenFile, page_index: u64) page_cache.Key {
    return .{
        .file_a = file.id.a,
        .file_b = file.id.b,
        .index = page_index,
        .start_cluster = file.start_cluster,
        .file_size = file.size,
        .attr = file.attr,
        .loc_cluster = file.loc_cluster,
        .loc_offset = file.loc_offset,
    };
}

fn openFromKey(key: page_cache.Key) filesystem.OpenFile {
    return .{
        .id = .{ .a = key.file_a, .b = key.file_b },
        .start_cluster = key.start_cluster,
        .size = key.file_size,
        .attr = key.attr,
        .loc_cluster = key.loc_cluster,
        .loc_offset = key.loc_offset,
    };
}

fn pageBuf(phys: u64) []u8 {
    return @as([*]u8, @ptrFromInt(address.physToVirt(phys)))[0..page_size];
}

fn ensureValid(
    ops: *const filesystem.Ops,
    file: filesystem.OpenFile,
    page_index: u64,
    slot: *page_cache.Slot,
) filesystem.Error!void {
    if (slot.valid) return;
    const buf = pageBuf(slot.phys);
    @memset(buf, 0);
    const offset = page_index * page_size;
    if (offset < file.size) {
        const want = @min(page_size, file.size - offset);
        const n = try ops.read(file, offset, buf[0..want]);
        if (n < want) @memset(buf[n..want], 0);
    }
    slot.valid = true;
}

fn writeback(key: page_cache.Key, phys: u64) page_cache.CacheError!void {
    const ops = bound_ops orelse return page_cache.CacheError.NotFound;
    var open = openFromKey(key);
    const offset = key.index * page_size;
    const buf = pageBuf(phys);
    const len = if (offset >= open.size) page_size else @min(page_size, open.size -% offset);
    // Always write a full page worth when dirty so partial updates persist.
    const write_len = if (len == 0) page_size else len;
    _ = ops.write_at(&open, offset, buf[0..write_len]) catch return page_cache.CacheError.OutOfMemory;
}

/// Bind filesystem ops used for miss populate and dirty writeback.
pub fn bindOps(ops: *const filesystem.Ops) void {
    bound_ops = ops;
    if (page_cache.ready()) {
        page_cache.global().setWriteback(writeback);
    }
}

/// Read file bytes through the page cache.
pub fn read(
    ops: *const filesystem.Ops,
    file: filesystem.OpenFile,
    offset: u64,
    buf: []u8,
) filesystem.Error!usize {
    if (!page_cache.ready()) return ops.read(file, offset, buf);
    if (offset >= file.size or buf.len == 0) return 0;

    const total = @min(buf.len, file.size - offset);
    var done: usize = 0;
    const cache = page_cache.global();

    while (done < total) {
        const file_off = offset + done;
        const page_index = file_off / page_size;
        const page_off: usize = @intCast(file_off % page_size);
        const chunk = @min(total - done, page_size - page_off);

        const key = keyFor(file, page_index);
        const slot = cache.getOrAlloc(key) catch return filesystem.Error.NoSpace;
        defer cache.unpin(key);

        try ensureValid(ops, file, page_index, slot);
        const page = pageBuf(slot.phys);
        @memcpy(buf[done .. done + chunk], page[page_off .. page_off + chunk]);
        done += chunk;
    }
    return total;
}

/// Write file bytes into the page cache (dirty); durable after fsync/eviction writeback.
pub fn write(
    ops: *const filesystem.Ops,
    file: *filesystem.OpenFile,
    offset: u64,
    buf: []const u8,
) filesystem.Error!usize {
    if (!page_cache.ready()) return ops.write_at(file, offset, buf);
    if (buf.len == 0) return 0;

    var done: usize = 0;
    const cache = page_cache.global();

    while (done < buf.len) {
        const file_off = offset + done;
        const page_index = file_off / page_size;
        const page_off: usize = @intCast(file_off % page_size);
        const chunk = @min(buf.len - done, page_size - page_off);

        var key = keyFor(file.*, page_index);
        const end_off = file_off + chunk;
        if (end_off > file.size) {
            file.size = @intCast(end_off);
            key.file_size = file.size;
        }

        const slot = cache.getOrAlloc(key) catch return filesystem.Error.NoSpace;
        defer cache.unpin(key);
        // Refresh metadata on the slot key for later writeback.
        slot.key = key;

        if (page_off != 0 or chunk != page_size) {
            try ensureValid(ops, file.*, page_index, slot);
        } else {
            slot.valid = true;
        }

        const page = pageBuf(slot.phys);
        @memcpy(page[page_off .. page_off + chunk], buf[done .. done + chunk]);
        cache.markDirty(key) catch {};
        done += chunk;
    }

    return buf.len;
}

pub fn fsync(ops: *const filesystem.Ops, file: *filesystem.OpenFile) filesystem.Error!void {
    _ = ops;
    if (!page_cache.ready()) return;
    page_cache.global().flushFile(file.id.a, file.id.b) catch return filesystem.Error.IoError;
    // Refresh size after writeback may have updated on-disk metadata via ops.
}

/// Populate (if needed) and pin a file page; caller must `unpinPage` when unmapped.
pub fn pinPage(ops: *const filesystem.Ops, file: filesystem.OpenFile, page_index: u64) filesystem.Error!u64 {
    if (!page_cache.ready()) return filesystem.Error.NotReady;
    const cache = page_cache.global();
    const key = keyFor(file, page_index);
    const slot = cache.getOrAlloc(key) catch return filesystem.Error.NoSpace;
    try ensureValid(ops, file, page_index, slot);
    return slot.phys;
}

pub fn unpinPage(file: filesystem.OpenFile, page_index: u64) void {
    if (!page_cache.ready()) return;
    page_cache.global().unpin(keyFor(file, page_index));
}

pub fn hits() u64 {
    if (!page_cache.ready()) return 0;
    return page_cache.global().hits;
}

pub fn misses() u64 {
    if (!page_cache.ready()) return 0;
    return page_cache.global().misses;
}
