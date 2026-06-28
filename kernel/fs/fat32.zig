const acpi_access = @import("../acpi/access.zig");
const virtio_blk = @import("../drivers/virtio_blk.zig");

pub const FatError = error{
    NotReady,
    InvalidBpb,
    NotFound,
    NotFile,
    IsDirectory,
    IoError,
    NameTooLong,
    PathTooLong,
    BufferTooSmall,
    Exists,
    NoSpace,
    NotEmpty,
};

pub const Entry = struct {
    start_cluster: u32,
    size: u32,
    attr: u8,
};

/// Location of a directory entry on disk (for updating size/cluster after writes).
pub const DirLoc = struct {
    cluster: u32,
    offset: u32,
};

pub const OpenResult = struct {
    entry: Entry,
    loc: DirLoc,
};

const Mount = struct {
    bytes_per_sector: u32,
    sectors_per_cluster: u32,
    reserved_sectors: u32,
    num_fats: u8,
    sectors_per_fat: u32,
    root_cluster: u32,
    fat_start_sector: u32,
    data_start_sector: u32,
    cluster_bytes: u32,
};

var mounted = false;
var fs: Mount = undefined;
var cluster_buf: [32768]u8 align(512) = undefined;
var next_free_hint: u32 = 2;

pub fn mount() FatError!void {
    if (!virtio_blk.isReady()) return FatError.NotReady;

    var boot: [512]u8 = undefined;
    try readSector(0, &boot);

    if (boot[510] != 0x55 or boot[511] != 0xAA) return FatError.InvalidBpb;
    const fs_type = boot[0x52 .. 0x52 + 8];
    if (!stdEq(fs_type, "FAT32   ") and !stdEq(fs_type, "FAT16   ") and !stdEq(fs_type, "FAT     ")) {
        return FatError.InvalidBpb;
    }

    const bytes_per_sector = acpi_access.readU16(&boot, 0x0B);
    const sectors_per_cluster = boot[0x0D];
    const reserved_sectors = acpi_access.readU16(&boot, 0x0E);
    const num_fats = boot[0x10];
    const sectors_per_fat = acpi_access.readU32(&boot, 0x24);
    const root_cluster = acpi_access.readU32(&boot, 0x2C);

    if (bytes_per_sector != virtio_blk.sector_size) return FatError.InvalidBpb;
    if (sectors_per_cluster == 0 or num_fats == 0) return FatError.InvalidBpb;

    const cluster_bytes = @as(u32, sectors_per_cluster) * bytes_per_sector;
    if (cluster_bytes > cluster_buf.len) return FatError.InvalidBpb;

    fs = .{
        .bytes_per_sector = bytes_per_sector,
        .sectors_per_cluster = sectors_per_cluster,
        .reserved_sectors = reserved_sectors,
        .num_fats = num_fats,
        .sectors_per_fat = sectors_per_fat,
        .root_cluster = root_cluster,
        .fat_start_sector = reserved_sectors,
        .data_start_sector = reserved_sectors + @as(u32, num_fats) * sectors_per_fat,
        .cluster_bytes = cluster_bytes,
    };
    next_free_hint = loadNextFreeHint(&boot) orelse 2;
    mounted = true;
}

pub fn isMounted() bool {
    return mounted;
}

pub fn lookup(path: []const u8) FatError!Entry {
    if (!mounted) return FatError.NotReady;

    var norm: [256]u8 = undefined;
    const clean = try normalizePath(path, &norm);

    if (clean.len == 0) {
        return .{
            .start_cluster = fs.root_cluster,
            .size = 0,
            .attr = 0x10,
        };
    }

    var cluster = fs.root_cluster;
    var component: []const u8 = clean;
    while (true) {
        const slash = indexOf(component, '/');
        const name = if (slash) |s| component[0..s] else component;
        const rest = if (slash) |s| component[s + 1 ..] else "";

        const entry = try findInDirectory(cluster, name);
        if (rest.len == 0) return entry;
        if (entry.attr & 0x10 == 0) return FatError.NotFound;
        cluster = entry.start_cluster;
        component = rest;
    }
}

pub fn read(entry: Entry, offset: u64, buf: []u8) FatError!usize {
    if (!mounted) return FatError.NotReady;
    if (entry.attr & 0x10 != 0) return FatError.IsDirectory;
    if (offset >= entry.size) return 0;

    const to_read = @min(buf.len, entry.size - @as(u32, @truncate(offset)));
    var copied: usize = 0;
    var file_off: u32 = @truncate(offset);
    var cluster = entry.start_cluster;

    if (file_off > 0) {
        const skip_clusters = file_off / fs.cluster_bytes;
        var i: u32 = 0;
        while (i < skip_clusters) : (i += 1) {
            cluster = try nextCluster(cluster);
        }
        file_off %= fs.cluster_bytes;
    }

    while (copied < to_read) {
        try readCluster(cluster, cluster_buf[0..fs.cluster_bytes]);
        const chunk_start = file_off;
        const chunk_len = @min(to_read - copied, fs.cluster_bytes - chunk_start);
        @memcpy(buf[copied .. copied + chunk_len], cluster_buf[chunk_start .. chunk_start + chunk_len]);
        copied += chunk_len;
        file_off = 0;
        if (copied < to_read) cluster = try nextCluster(cluster);
    }

    return copied;
}

/// Open an existing file for read/write, optionally truncating it.
pub fn openFile(path: []const u8, truncate: bool) FatError!OpenResult {
    if (!mounted) return FatError.NotReady;

    var norm: [256]u8 = undefined;
    const clean = try normalizePath(path, &norm);
    if (clean.len == 0) return FatError.IsDirectory;

    const parent_cluster = try lookupParentCluster(clean);
    const name = parentName(clean);
    var result = try findInDirectoryWithLoc(parent_cluster, name);

    if (result.entry.attr & 0x10 != 0) return FatError.IsDirectory;
    if (truncate) try truncateFile(&result.entry, result.loc);
    return result;
}

/// Create a new file (fails if it already exists).
pub fn createFile(path: []const u8) FatError!OpenResult {
    if (!mounted) return FatError.NotReady;

    var norm: [256]u8 = undefined;
    const clean = try normalizePath(path, &norm);
    if (clean.len == 0) return FatError.IsDirectory;

    const parent_cluster = try lookupParentCluster(clean);
    const name = parentName(clean);

    if (findInDirectoryWithLoc(parent_cluster, name)) |_| return FatError.Exists else |_| {}

    var name83: [11]u8 = undefined;
    try toShortName(name, &name83);

    const loc = try findFreeDentSlot(parent_cluster);
    const cluster = try allocCluster();

    const entry: Entry = .{
        .start_cluster = cluster,
        .size = 0,
        .attr = 0x20, // archive
    };
    try writeDirEntry(loc, &name83, entry);

    return .{ .entry = entry, .loc = loc };
}

/// Create a new directory (fails if it already exists).
pub fn createDirectory(path: []const u8) FatError!void {
    if (!mounted) return FatError.NotReady;

    var norm: [256]u8 = undefined;
    const clean = try normalizePath(path, &norm);
    if (clean.len == 0) return FatError.Exists;

    const parent_cluster = try lookupParentCluster(clean);
    const name = parentName(clean);

    if (findInDirectoryWithLoc(parent_cluster, name)) |_| return FatError.Exists else |_| {}

    var name83: [11]u8 = undefined;
    try toShortName(name, &name83);

    const loc = try findFreeDentSlot(parent_cluster);
    const cluster = try allocCluster();
    try initDirectoryCluster(cluster, parent_cluster);

    const entry: Entry = .{
        .start_cluster = cluster,
        .size = 0,
        .attr = 0x10,
    };
    try writeDirEntry(loc, &name83, entry);
}

/// Remove an empty directory: free its clusters and mark the directory entry deleted.
pub fn removeDirectory(path: []const u8) FatError!DirLoc {
    if (!mounted) return FatError.NotReady;

    var norm: [256]u8 = undefined;
    const clean = try normalizePath(path, &norm);
    if (clean.len == 0) return FatError.IsDirectory;

    const parent_cluster = try lookupParentCluster(clean);
    const name = parentName(clean);
    const result = try findInDirectoryWithLoc(parent_cluster, name);

    if (result.entry.attr & 0x10 == 0) return FatError.NotFile;
    if (!try directoryIsEmpty(result.entry.start_cluster)) return FatError.NotEmpty;
    if (result.entry.start_cluster >= 2) try freeChain(result.entry.start_cluster);

    try readCluster(result.loc.cluster, cluster_buf[0..fs.cluster_bytes]);
    const off: usize = @intCast(result.loc.offset);
    if (off + 32 > fs.cluster_bytes) return FatError.IoError;
    cluster_buf[off] = 0xE5;
    try writeCluster(result.loc.cluster, cluster_buf[0..fs.cluster_bytes]);
    return result.loc;
}

fn directoryIsEmpty(dir_cluster: u32) FatError!bool {
    var cluster = dir_cluster;
    while (cluster >= 2 and cluster < 0x0FFFFFF8) {
        try readCluster(cluster, cluster_buf[0..fs.cluster_bytes]);
        var off: usize = 0;
        while (off + 32 <= fs.cluster_bytes) {
            const entry = cluster_buf[off .. off + 32];
            if (entry[0] == 0) return true;
            if (entry[0] == 0xE5 or entry[0] == 0x2E) {
                off += 32;
                continue;
            }
            if (entry[11] == 0x0F) {
                off += 32;
                continue;
            }
            return false;
        }
        cluster = nextCluster(cluster) catch return true;
    }
    return true;
}

fn initDirectoryCluster(cluster: u32, parent_cluster: u32) FatError!void {
    @memset(cluster_buf[0..fs.cluster_bytes], 0);
    writeDotEntry(0, cluster);
    writeDotEntry(32, parent_cluster);
    try writeCluster(cluster, cluster_buf[0..fs.cluster_bytes]);
}

fn writeDotEntry(off: usize, target_cluster: u32) void {
    if (off + 32 > fs.cluster_bytes) return;
    if (off == 0) {
        cluster_buf[off] = '.';
    } else {
        cluster_buf[off] = '.';
        cluster_buf[off + 1] = '.';
    }
    cluster_buf[off + 11] = 0x10;
    const hi: u16 = @truncate(target_cluster >> 16);
    const lo: u16 = @truncate(target_cluster & 0xFFFF);
    writeU16Le(cluster_buf[off..], 20, hi);
    writeU16Le(cluster_buf[off..], 26, lo);
}

pub fn writeAt(result: *OpenResult, offset: u64, buf: []const u8) FatError!usize {
    if (!mounted) return FatError.NotReady;
    if (result.entry.attr & 0x10 != 0) return FatError.IsDirectory;

    const n = try writeEntryData(&result.entry, offset, buf);
    try patchDirEntry(result.loc, result.entry);
    return n;
}

/// Delete a regular file: free its clusters and mark the directory entry deleted.
pub fn unlinkFile(path: []const u8) FatError!DirLoc {
    if (!mounted) return FatError.NotReady;

    var norm: [256]u8 = undefined;
    const clean = try normalizePath(path, &norm);
    if (clean.len == 0) return FatError.IsDirectory;

    const parent_cluster = try lookupParentCluster(clean);
    const name = parentName(clean);
    const result = try findInDirectoryWithLoc(parent_cluster, name);

    if (result.entry.attr & 0x10 != 0) return FatError.IsDirectory;
    if (result.entry.start_cluster >= 2) try freeChain(result.entry.start_cluster);

    try readCluster(result.loc.cluster, cluster_buf[0..fs.cluster_bytes]);
    const off: usize = @intCast(result.loc.offset);
    if (off + 32 > fs.cluster_bytes) return FatError.IoError;
    cluster_buf[off] = 0xE5;
    try writeCluster(result.loc.cluster, cluster_buf[0..fs.cluster_bytes]);
    return result.loc;
}

fn truncateFile(entry: *Entry, loc: DirLoc) FatError!void {
    if (entry.start_cluster >= 2) try freeChain(entry.start_cluster);
    entry.start_cluster = try allocCluster();
    entry.size = 0;
    try patchDirEntry(loc, entry.*);
}

fn writeEntryData(entry: *Entry, offset: u64, buf: []const u8) FatError!usize {
    if (buf.len == 0) return 0;

    var written: usize = 0;
    var file_off: u32 = @truncate(offset);
    var cluster = entry.start_cluster;

    if (file_off > 0) {
        const skip_clusters = file_off / fs.cluster_bytes;
        var i: u32 = 0;
        while (i < skip_clusters) : (i += 1) {
            cluster = try nextCluster(cluster);
        }
        file_off %= fs.cluster_bytes;
    }

    while (written < buf.len) {
        try readCluster(cluster, cluster_buf[0..fs.cluster_bytes]);
        const chunk_start = file_off;
        const chunk_len = @min(buf.len - written, fs.cluster_bytes - chunk_start);
        @memcpy(cluster_buf[chunk_start .. chunk_start + chunk_len], buf[written .. written + chunk_len]);
        try writeCluster(cluster, cluster_buf[0..fs.cluster_bytes]);

        written += chunk_len;
        file_off = 0;

        if (written < buf.len) {
            cluster = try nextClusterOrExtend(cluster);
        }
    }

    const end_off = offset + written;
    if (end_off > entry.size) entry.size = @truncate(end_off);
    return written;
}

fn nextClusterOrExtend(cluster: u32) FatError!u32 {
    const next = getFatEntry(cluster) catch return FatError.IoError;
    if (next >= 2 and next < 0x0FFFFFF8) return next;

    const new_cluster = try allocCluster();
    try setFatEntry(cluster, new_cluster);
    return new_cluster;
}

fn patchDirEntry(loc: DirLoc, entry: Entry) FatError!void {
    try readCluster(loc.cluster, cluster_buf[0..fs.cluster_bytes]);
    const off: usize = @intCast(loc.offset);
    if (off + 32 > fs.cluster_bytes) return FatError.IoError;

    const hi: u16 = @truncate(entry.start_cluster >> 16);
    const lo: u16 = @truncate(entry.start_cluster & 0xFFFF);
    writeU16Le(cluster_buf[off..], 20, hi);
    writeU16Le(cluster_buf[off..], 26, lo);
    writeU32Le(cluster_buf[off..], 28, entry.size);
    cluster_buf[off + 11] = entry.attr;
    try writeCluster(loc.cluster, cluster_buf[0..fs.cluster_bytes]);
}

fn writeDirEntry(loc: DirLoc, name83: *const [11]u8, entry: Entry) FatError!void {
    try readCluster(loc.cluster, cluster_buf[0..fs.cluster_bytes]);
    const off: usize = @intCast(loc.offset);
    if (off + 32 > fs.cluster_bytes) return FatError.IoError;

    @memset(cluster_buf[off .. off + 32], 0);
    @memcpy(cluster_buf[off .. off + 11], name83);
    cluster_buf[off + 11] = entry.attr;
    const hi: u16 = @truncate(entry.start_cluster >> 16);
    const lo: u16 = @truncate(entry.start_cluster & 0xFFFF);
    writeU16Le(cluster_buf[off..], 20, hi);
    writeU16Le(cluster_buf[off..], 26, lo);
    writeU32Le(cluster_buf[off..], 28, entry.size);
    try writeCluster(loc.cluster, cluster_buf[0..fs.cluster_bytes]);
}

fn findFreeDentSlot(dir_cluster: u32) FatError!DirLoc {
    var cluster = dir_cluster;
    var last_cluster = dir_cluster;

    while (cluster >= 2 and cluster < 0x0FFFFFF8) {
        last_cluster = cluster;
        try readCluster(cluster, cluster_buf[0..fs.cluster_bytes]);
        var off: usize = 0;
        while (off + 32 <= fs.cluster_bytes) {
            const entry = cluster_buf[off .. off + 32];
            if (entry[0] == 0x00 or entry[0] == 0xE5) {
                return .{ .cluster = cluster, .offset = @intCast(off) };
            }
            off += 32;
        }
        cluster = getFatEntry(cluster) catch return FatError.IoError;
        if (cluster >= 2 and cluster < 0x0FFFFFF8) continue;
        break;
    }

    const new_cluster = try allocCluster();
    try setFatEntry(last_cluster, new_cluster);
    @memset(cluster_buf[0..fs.cluster_bytes], 0);
    try writeCluster(new_cluster, cluster_buf[0..fs.cluster_bytes]);
    return .{ .cluster = new_cluster, .offset = 0 };
}

fn loadNextFreeHint(boot: *const [512]u8) ?u32 {
    const fsinfo_sector = acpi_access.readU16(boot, 0x42);
    if (fsinfo_sector == 0) return null;

    var sector: [512]u8 = undefined;
    readSector(fsinfo_sector, &sector) catch return null;
    if (acpi_access.readU32(&sector, 0) != 0x4161_5252) return null;
    if (acpi_access.readU32(&sector, 0x1E4) != 0x6141_7272) return null;

    const next = acpi_access.readU32(&sector, 0x1EC);
    if (next < 2 or next >= 0x0FFF_FFF0) return null;
    return next;
}

fn maxDataCluster() u32 {
    const cap = virtio_blk.capacity();
    if (cap <= fs.data_start_sector) return 2;
    const data_sectors = cap - fs.data_start_sector;
    const clusters = data_sectors / fs.sectors_per_cluster;
    return @intCast(@min(clusters + 2, 0x0FFF_FFF0));
}

fn allocCluster() FatError!u32 {
    const limit = maxDataCluster();
    var cluster = if (next_free_hint >= 2 and next_free_hint < limit) next_free_hint else 2;
    while (cluster < limit) : (cluster += 1) {
        const value = getFatEntry(cluster) catch continue;
        if (value == 0) {
            try setFatEntry(cluster, 0x0FFF_FFF8);
            @memset(cluster_buf[0..fs.cluster_bytes], 0);
            try writeCluster(cluster, cluster_buf[0..fs.cluster_bytes]);
            next_free_hint = cluster + 1;
            return cluster;
        }
    }
    return FatError.NoSpace;
}

fn freeChain(start: u32) FatError!void {
    var cluster = start;
    var hops: u32 = 0;
    while (cluster >= 2 and cluster < 0x0FFFFFF8) : (hops += 1) {
        if (hops > 65536) return FatError.IoError;
        const next = getFatEntry(cluster) catch break;
        try setFatEntry(cluster, 0);
        cluster = next;
    }
}

fn getFatEntry(cluster: u32) FatError!u32 {
    const fat_offset = @as(u64, cluster) * 4;
    const fat_sector = fs.fat_start_sector + @as(u32, @truncate(fat_offset / fs.bytes_per_sector));
    const fat_off = @as(usize, @truncate(fat_offset % fs.bytes_per_sector));

    var sector: [512]u8 = undefined;
    try readSector(fat_sector, &sector);
    return acpi_access.readU32(&sector, fat_off) & 0x0FFF_FFFF;
}

fn setFatEntry(cluster: u32, value: u32) FatError!void {
    const fat_offset = @as(u64, cluster) * 4;
    const fat_sector_base = fs.fat_start_sector + @as(u32, @truncate(fat_offset / fs.bytes_per_sector));
    const fat_off = @as(usize, @truncate(fat_offset % fs.bytes_per_sector));

    var fat_idx: u32 = 0;
    while (fat_idx < fs.num_fats) : (fat_idx += 1) {
        const fat_sector = fat_sector_base + fat_idx * fs.sectors_per_fat;
        var sector: [512]u8 = undefined;
        try readSector(fat_sector, &sector);
        const existing = acpi_access.readU32(&sector, fat_off);
        const merged = (existing & 0xF000_0000) | (value & 0x0FFF_FFFF);
        writeU32Le(&sector, fat_off, merged);
        try writeSector(fat_sector, &sector);
    }
}

fn lookupParentCluster(clean: []const u8) FatError!u32 {
    if (lastIndexOf(clean, '/')) |slash| {
        if (slash == 0) return fs.root_cluster;
        const parent = try lookup(clean[0..slash]);
        if (parent.attr & 0x10 == 0) return FatError.NotFound;
        return parent.start_cluster;
    }
    return fs.root_cluster;
}

fn parentName(clean: []const u8) []const u8 {
    if (lastIndexOf(clean, '/')) |slash| return clean[slash + 1 ..];
    return clean;
}

fn findInDirectoryWithLoc(dir_cluster: u32, name: []const u8) FatError!OpenResult {
    var name83: [11]u8 = undefined;
    try toShortName(name, &name83);

    var cluster = dir_cluster;
    while (cluster >= 2 and cluster < 0x0FFFFFF8) {
        try readCluster(cluster, cluster_buf[0..fs.cluster_bytes]);
        var off: usize = 0;
        while (off + 32 <= fs.cluster_bytes) {
            const entry = cluster_buf[off .. off + 32];
            if (entry[0] == 0) return FatError.NotFound;
            if (entry[0] == 0xE5 or entry[0] == 0x2E) {
                off += 32;
                continue;
            }
            if (entry[11] == 0x0F) {
                off += 32;
                continue;
            }
            if (stdEq(entry[0..11], &name83)) {
                const hi = acpi_access.readU16(entry.ptr, 20);
                const lo = acpi_access.readU16(entry.ptr, 26);
                const start = (@as(u32, hi) << 16) | lo;
                return .{
                    .entry = .{
                        .start_cluster = start,
                        .size = acpi_access.readU32(entry.ptr, 28),
                        .attr = entry[11],
                    },
                    .loc = .{ .cluster = cluster, .offset = @intCast(off) },
                };
            }
            off += 32;
        }
        cluster = nextCluster(cluster) catch return FatError.NotFound;
    }
    return FatError.NotFound;
}

/// List directory entries at `path`, writing newline-separated names into `out`.
pub fn listDir(path: []const u8, out: []u8) FatError!usize {
    if (!mounted) return FatError.NotReady;

    const dir = try lookup(path);
    if (dir.attr & 0x10 == 0) return FatError.NotFile;
    return listInDirectory(dir.start_cluster, out);
}

fn listInDirectory(dir_cluster: u32, out: []u8) FatError!usize {
    var pos: usize = 0;
    var cluster = dir_cluster;
    var name_buf: [13]u8 = undefined;

    while (cluster >= 2 and cluster < 0x0FFFFFF8) {
        try readCluster(cluster, cluster_buf[0..fs.cluster_bytes]);
        var off: usize = 0;
        while (off + 32 <= fs.cluster_bytes) {
            const entry = cluster_buf[off .. off + 32];
            if (entry[0] == 0) return pos;
            if (entry[0] == 0xE5 or entry[0] == 0x2E) {
                off += 32;
                continue;
            }
            if (entry[11] == 0x0F) {
                off += 32;
                continue;
            }
            // Skip volume label, hidden, and system entries (e.g. macOS metadata).
            if (entry[11] & 0x0E != 0) {
                off += 32;
                continue;
            }

            var short: [11]u8 = undefined;
            @memcpy(&short, entry[0..11]);
            const name = formatShortName(&short, &name_buf);
            if (name.len == 0) {
                off += 32;
                continue;
            }
            if (pos + name.len + 1 > out.len) return FatError.BufferTooSmall;

            @memcpy(out[pos .. pos + name.len], name);
            pos += name.len;
            out[pos] = '\n';
            pos += 1;
            off += 32;
        }
        cluster = try nextCluster(cluster);
    }
    return pos;
}

fn formatShortName(short: *const [11]u8, out: *[13]u8) []const u8 {
    var base_len: usize = 8;
    while (base_len > 0 and short[base_len - 1] == ' ') base_len -= 1;

    var ext_len: usize = 3;
    while (ext_len > 0 and short[7 + ext_len] == ' ') ext_len -= 1;

    var len: usize = 0;
    @memcpy(out[0..base_len], short[0..base_len]);
    len = base_len;
    if (ext_len > 0) {
        out[len] = '.';
        len += 1;
        @memcpy(out[len .. len + ext_len], short[8 .. 8 + ext_len]);
        len += ext_len;
    }
    return out[0..len];
}

fn findInDirectory(dir_cluster: u32, name: []const u8) FatError!Entry {
    var name83: [11]u8 = undefined;
    try toShortName(name, &name83);

    var cluster = dir_cluster;
    while (cluster >= 2 and cluster < 0x0FFFFFF8) {
        try readCluster(cluster, cluster_buf[0..fs.cluster_bytes]);
        var off: usize = 0;
        while (off + 32 <= fs.cluster_bytes) {
            const entry = cluster_buf[off .. off + 32];
            if (entry[0] == 0) return FatError.NotFound;
            if (entry[0] == 0xE5 or entry[0] == 0x2E) {
                off += 32;
                continue;
            }
            if (entry[11] == 0x0F) {
                off += 32;
                continue;
            }
            if (stdEq(entry[0..11], &name83)) {
                const hi = acpi_access.readU16(entry.ptr, 20);
                const lo = acpi_access.readU16(entry.ptr, 26);
                const start = (@as(u32, hi) << 16) | lo;
                return .{
                    .start_cluster = start,
                    .size = acpi_access.readU32(entry.ptr, 28),
                    .attr = entry[11],
                };
            }
            off += 32;
        }
        cluster = nextCluster(cluster) catch return FatError.NotFound;
    }
    return FatError.NotFound;
}

fn nextCluster(cluster: u32) FatError!u32 {
    const next = getFatEntry(cluster) catch return FatError.IoError;
    if (next < 2 or next >= 0x0FFF_FFF8) return FatError.IoError;
    return next;
}

fn writeCluster(cluster: u32, buf: []const u8) FatError!void {
    const first_sector = fs.data_start_sector + (cluster - 2) * fs.sectors_per_cluster;
    var i: u32 = 0;
    while (i < fs.sectors_per_cluster) : (i += 1) {
        const sector_buf = buf[@as(usize, i) * fs.bytes_per_sector ..][0..fs.bytes_per_sector];
        try writeSector(first_sector + i, sector_buf);
    }
}

fn readCluster(cluster: u32, buf: []u8) FatError!void {
    const first_sector = fs.data_start_sector + (cluster - 2) * fs.sectors_per_cluster;
    var i: u32 = 0;
    while (i < fs.sectors_per_cluster) : (i += 1) {
        const sector_buf = buf[@as(usize, i) * fs.bytes_per_sector ..][0..fs.bytes_per_sector];
        try readSector(first_sector + i, sector_buf);
    }
}

fn readSector(lba: u64, buf: []u8) FatError!void {
    virtio_blk.readSectors(lba, buf) catch return FatError.IoError;
}

fn writeSector(lba: u64, buf: []const u8) FatError!void {
    virtio_blk.writeSectors(lba, buf) catch return FatError.IoError;
}

fn writeU16Le(buf: []u8, off: usize, value: u16) void {
    buf[off] = @truncate(value);
    buf[off + 1] = @truncate(value >> 8);
}

fn writeU32Le(buf: []u8, off: usize, value: u32) void {
    buf[off] = @truncate(value);
    buf[off + 1] = @truncate(value >> 8);
    buf[off + 2] = @truncate(value >> 16);
    buf[off + 3] = @truncate(value >> 24);
}

fn lastIndexOf(hay: []const u8, needle: u8) ?usize {
    var i = hay.len;
    while (i > 0) : (i -= 1) {
        if (hay[i - 1] == needle) return i - 1;
    }
    return null;
}

fn normalizePath(path: []const u8, out: []u8) FatError![]const u8 {
    if (path.len >= out.len) return FatError.PathTooLong;

    var len: usize = 0;
    var i: usize = 0;
    while (i < path.len) : (i += 1) {
        if (path[i] == '/') continue;
        const start = i;
        while (i < path.len and path[i] != '/') : (i += 1) {}
        const part = path[start..i];
        if (part.len == 0) continue;
        if (stdEq(part, ".") or stdEq(part, "..")) return FatError.NotFound;
        if (len != 0) {
            out[len] = '/';
            len += 1;
        }
        if (len + part.len >= out.len) return FatError.PathTooLong;
        @memcpy(out[len .. len + part.len], part);
        len += part.len;
        if (i < path.len and path[i] == '/') {}
    }
    return out[0..len];
}

fn toShortName(name: []const u8, out: *[11]u8) FatError!void {
    @memset(out, ' ');

    const dot = indexOf(name, '.');
    const base = if (dot) |d| name[0..d] else name;
    const ext = if (dot) |d| name[d + 1 ..] else "";

    if (base.len == 0 or base.len > 8 or ext.len > 3) return FatError.NameTooLong;

    var i: usize = 0;
    while (i < base.len) : (i += 1) {
        out[i] = toUpper(base[i]);
    }
    i = 0;
    while (i < ext.len) : (i += 1) {
        out[8 + i] = toUpper(ext[i]);
    }
}

fn toUpper(c: u8) u8 {
    if (c >= 'a' and c <= 'z') return c - 32;
    return c;
}

fn indexOf(hay: []const u8, needle: u8) ?usize {
    for (hay, 0..) |c, i| {
        if (c == needle) return i;
    }
    return null;
}

fn stdEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (x != y) return false;
    }
    return true;
}
