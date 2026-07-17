const process = @import("../proc/process.zig");
const vma = @import("vma.zig");
const demand = @import("demand.zig");
const paging = @import("../arch/x86_64/paging.zig");
const errno = @import("../syscall/errno.zig");
const fdtab = @import("../syscall/fd.zig");
const runtime = @import("../runtime.zig");
const filesystem = @import("../fs/filesystem.zig");
const file_cache = @import("../fs/file_cache.zig");

/// Anonymous mmap arena: below the stack guard, above the ELF/heap base.
pub const mmap_floor: u64 = process.user_brk_base;
pub const mmap_ceiling: u64 = process.user_brk_limit;

fn alignUp(n: u64, align_to: u64) u64 {
    return (n + align_to - 1) & ~(align_to - 1);
}

fn findAnonHole(proc: *const process.Process, len: u64) ?u64 {
    if (len == 0 or len > mmap_ceiling - mmap_floor) return null;
    var end = mmap_ceiling;
    while (end >= mmap_floor + len) {
        const base = end - len;
        if (base < proc.brk) break;
        if (!proc.vmas.hasOverlap(base, len)) return base;
        end -= paging.page_size;
    }
    return null;
}

fn pickBase(proc: *process.Process, addr: u64, map_len: u64, fixed: bool) i64 {
    if (fixed) {
        if (addr == 0 or addr % paging.page_size != 0) return errno.EINVAL;
        if (addr < mmap_floor or addr > mmap_ceiling or map_len > mmap_ceiling - addr) {
            return errno.EINVAL;
        }
        if (proc.vmas.hasOverlap(addr, map_len)) return errno.EINVAL;
        return @bitCast(@as(i64, @intCast(addr)));
    }
    const base = findAnonHole(proc, map_len) orelse return errno.ENOMEM;
    return @bitCast(@as(i64, @intCast(base)));
}

pub fn sysMmap(
    proc: *process.Process,
    addr: u64,
    len: u64,
    prot_u: u64,
    flags_u: u64,
    fd: u64,
    offset: u64,
) i64 {
    if (len == 0) return errno.EINVAL;
    const prot: u32 = @truncate(prot_u);
    const flags: u32 = @truncate(flags_u);

    if (vma.violatesWx(prot)) return errno.EINVAL;

    const anon = flags & vma.MAP_ANONYMOUS != 0;
    const priv = flags & vma.MAP_PRIVATE != 0;
    const fixed = flags & vma.MAP_FIXED != 0;
    const supported = vma.MAP_ANONYMOUS | vma.MAP_PRIVATE | vma.MAP_FIXED;
    if (flags & ~supported != 0) return errno.EINVAL;
    if (!priv) return errno.EINVAL;

    const map_len = alignUp(len, paging.page_size);
    const base_or_err = pickBase(proc, addr, map_len, fixed);
    if (base_or_err < 0) return base_or_err;
    const base: u64 = @intCast(base_or_err);

    if (anon) {
        const fd_ignorable = fd == @as(u64, @bitCast(@as(i64, -1))) or fd == 0;
        if (!fd_ignorable) return errno.EBADF;

        proc.vmas.insert(.{
            .base = base,
            .len = map_len,
            .prot = prot,
            .flags = flags,
            .kind = .anon,
        }) catch |err| switch (err) {
            vma.VmaError.OutOfSlots => return errno.ENOMEM,
            vma.VmaError.Overlap, vma.VmaError.InvalidRange, vma.VmaError.NotFound => return errno.EINVAL,
        };
        return @bitCast(@as(i64, @intCast(base)));
    }

    // File-backed MAP_PRIVATE: read-only for now.
    if (prot & vma.PROT_WRITE != 0) return errno.EINVAL;
    if (offset % paging.page_size != 0) return errno.EINVAL;

    const handle = fdtab.expectFile(fd) catch return errno.EBADF;
    const h = runtime.boot().vfs.getHandle(handle) catch return errno.EBADF;
    if (h.is_directory) return errno.EACCES;

    proc.vmas.insert(.{
        .base = base,
        .len = map_len,
        .prot = prot,
        .flags = flags,
        .kind = .file,
        .file = .{
            .file_a = h.open.id.a,
            .file_b = h.open.id.b,
            .file_offset = offset,
            .start_cluster = h.open.start_cluster,
            .file_size = h.open.size,
            .attr = h.open.attr,
            .loc_cluster = h.open.loc_cluster,
            .loc_offset = h.open.loc_offset,
        },
    }) catch |err| switch (err) {
        vma.VmaError.OutOfSlots => return errno.ENOMEM,
        vma.VmaError.Overlap, vma.VmaError.InvalidRange, vma.VmaError.NotFound => return errno.EINVAL,
    };
    return @bitCast(@as(i64, @intCast(base)));
}

fn openFileFromVma(region: vma.Vma) filesystem.OpenFile {
    return .{
        .id = .{ .a = region.file.file_a, .b = region.file.file_b },
        .start_cluster = region.file.start_cluster,
        .size = region.file.file_size,
        .attr = region.file.attr,
        .loc_cluster = region.file.loc_cluster,
        .loc_offset = region.file.loc_offset,
    };
}

fn unpinFileRange(proc: *process.Process, base: u64, len: u64) void {
    var page = base;
    const end = base + len;
    while (page < end) : (page += paging.page_size) {
        const region = proc.vmas.find(page) orelse continue;
        if (region.kind != .file) continue;
        if (paging.getPhysIn(proc.address_space.cr3, page) == null) continue;
        const page_index = (region.file.file_offset + (page - region.base)) / paging.page_size;
        file_cache.unpinPage(&@import("../fs/fat32.zig").ops, openFileFromVma(region), page_index);
    }
}

/// Pin cache pages for every present file-backed mapping (e.g. after COW fork share).
pub fn retainFileCachePins(proc: *process.Process) void {
    for (proc.vmas.slots) |region| {
        if (region.kind != .file) continue;
        var page = region.base;
        const end = region.end();
        while (page < end) : (page += paging.page_size) {
            if (paging.getPhysIn(proc.address_space.cr3, page) == null) continue;
            const page_index = (region.file.file_offset + (page - region.base)) / paging.page_size;
            const open = openFileFromVma(region);
            // getOrAlloc pins; page already populated in parent.
            _ = file_cache.pinPage(&@import("../fs/fat32.zig").ops, open, page_index) catch {};
        }
    }
}

/// Drop cache pins for present file-backed pages before tearing down the address space.
pub fn releaseFileCachePins(proc: *process.Process) void {
    for (proc.vmas.slots) |region| {
        if (region.kind != .file) continue;
        unpinFileRange(proc, region.base, region.len);
    }
}

pub fn sysMunmap(proc: *process.Process, addr: u64, len: u64) i64 {
    if (len == 0) return errno.EINVAL;
    if (addr % paging.page_size != 0) return errno.EINVAL;
    const map_len = alignUp(len, paging.page_size);

    var page = addr;
    const end = addr + map_len;
    while (page < end) : (page += paging.page_size) {
        if (proc.vmas.find(page) == null) return errno.EINVAL;
    }

    unpinFileRange(proc, addr, map_len);
    proc.address_space.unmapUserRange(addr, map_len);
    proc.vmas.unmapRange(addr, map_len) catch return errno.EINVAL;
    return 0;
}

pub fn sysMprotect(proc: *process.Process, addr: u64, len: u64, prot_u: u64) i64 {
    if (len == 0) return errno.EINVAL;
    if (addr % paging.page_size != 0) return errno.EINVAL;
    const prot: u32 = @truncate(prot_u);
    if (vma.violatesWx(prot)) return errno.EINVAL;

    const map_len = alignUp(len, paging.page_size);
    var page = addr;
    const end = addr + map_len;
    while (page < end) : (page += paging.page_size) {
        if (proc.vmas.find(page) == null) return errno.ENOMEM;
        // File-backed mappings stay read-only for now.
        if (proc.vmas.find(page).?.kind == .file and prot & vma.PROT_WRITE != 0) {
            return errno.EINVAL;
        }
    }

    proc.vmas.setProt(addr, map_len, prot) catch return errno.ENOMEM;

    const perm = demand.pteFromProt(prot);
    page = addr;
    while (page < end) : (page += paging.page_size) {
        if (paging.getPhysIn(proc.address_space.cr3, page)) |phys| {
            paging.remapUserPageIn(proc.address_space.cr3, page, phys, perm) catch return errno.ENOMEM;
            if (paging.readCr3() == proc.address_space.cr3) paging.invlpg(page);
        }
    }
    return 0;
}
