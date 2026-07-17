const process = @import("../proc/process.zig");
const vma = @import("vma.zig");
const paging = @import("../arch/x86_64/paging.zig");
const errno = @import("../syscall/errno.zig");

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

pub fn sysMmap(
    proc: *process.Process,
    addr: u64,
    len: u64,
    prot_u: u64,
    flags_u: u64,
    fd: u64,
    offset: u64,
) i64 {
    _ = offset;
    if (len == 0) return errno.EINVAL;
    const prot: u32 = @truncate(prot_u);
    const flags: u32 = @truncate(flags_u);

    if (vma.violatesWx(prot)) return errno.EINVAL;

    const anon = flags & vma.MAP_ANONYMOUS != 0;
    const priv = flags & vma.MAP_PRIVATE != 0;
    const fixed = flags & vma.MAP_FIXED != 0;
    const supported = vma.MAP_ANONYMOUS | vma.MAP_PRIVATE | vma.MAP_FIXED;
    if (flags & ~supported != 0) return errno.EINVAL;
    if (!anon or !priv) return errno.EINVAL;

    // Linux passes fd=-1 for anonymous maps; also accept 0 when ANONYMOUS is set.
    const fd_ignorable = fd == @as(u64, @bitCast(@as(i64, -1))) or fd == 0;
    if (!fd_ignorable) return errno.EBADF;

    const map_len = alignUp(len, paging.page_size);
    const base: u64 = if (fixed) blk: {
        if (addr == 0 or addr % paging.page_size != 0) return errno.EINVAL;
        if (addr < mmap_floor or addr > mmap_ceiling or map_len > mmap_ceiling - addr) {
            return errno.EINVAL;
        }
        if (proc.vmas.hasOverlap(addr, map_len)) return errno.EINVAL;
        break :blk addr;
    } else blk: {
        break :blk findAnonHole(proc, map_len) orelse return errno.ENOMEM;
    };

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

    // Lazy: no physical pages until first touch (demand-zero #PF).
    return @bitCast(@as(i64, @intCast(base)));
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

    proc.address_space.unmapUserRange(addr, map_len);
    proc.vmas.unmapRange(addr, map_len) catch return errno.EINVAL;
    return 0;
}
