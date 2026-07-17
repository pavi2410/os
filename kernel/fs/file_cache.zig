const address = @import("../mm/address.zig");
const filesystem = @import("filesystem.zig");
const page_cache = @import("../mm/page_cache.zig");
const paging = @import("../arch/x86_64/paging.zig");

const page_size = paging.page_size;

fn keyFor(file: filesystem.OpenFile, page_index: u64) page_cache.Key {
    return .{
        .file_a = file.id.a,
        .file_b = file.id.b,
        .index = page_index,
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

/// Write file bytes through the page cache (marks dirty; caller may write-through).
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

        const key = keyFor(file.*, page_index);
        const slot = cache.getOrAlloc(key) catch return filesystem.Error.NoSpace;
        defer cache.unpin(key);

        // Partial page write needs existing contents.
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

    // Write-through for durability until fsync-based writeback lands.
    return ops.write_at(file, offset, buf);
}

pub fn hits() u64 {
    if (!page_cache.ready()) return 0;
    return page_cache.global().hits;
}

pub fn misses() u64 {
    if (!page_cache.ready()) return 0;
    return page_cache.global().misses;
}
