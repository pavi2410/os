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
};

pub const Entry = struct {
    start_cluster: u32,
    size: u32,
    attr: u8,
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
        cluster = try nextCluster(cluster);
    }
    return FatError.NotFound;
}

fn nextCluster(cluster: u32) FatError!u32 {
    const fat_offset = @as(u64, cluster) * 4;
    const fat_sector = fs.fat_start_sector + @as(u32, @truncate(fat_offset / fs.bytes_per_sector));
    const fat_off = @as(usize, @truncate(fat_offset % fs.bytes_per_sector));

    var sector: [512]u8 = undefined;
    try readSector(fat_sector, &sector);
    const next = acpi_access.readU32(&sector, fat_off) & 0x0FFF_FFFF;
    if (next < 2 or next >= 0x0FFF_FFF8) return FatError.IoError;
    return next;
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
