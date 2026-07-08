const bytes = @import("common/bytes");
const block = @import("../../drivers/block.zig");
const filesystem = @import("../filesystem.zig");

pub const FatError = filesystem.FatError;

pub const Entry = struct {
    start_cluster: u32,
    size: u32,
    attr: u8,
};

pub const DirLoc = struct {
    cluster: u32,
    offset: u32,
};

pub const OpenResult = struct {
    entry: Entry,
    loc: DirLoc,
};

pub const Mount = struct {
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
var disk: ?*const block.Device = null;
pub var cluster_buf: [32768]u8 align(512) = undefined;
var next_free_hint: u32 = 2;

pub fn isMounted() bool {
    return mounted;
}

pub fn setMounted(value: bool) void {
    mounted = value;
}

pub fn mountParams() Mount {
    return fs;
}

pub fn setMountParams(params: Mount) void {
    fs = params;
}

pub fn setDisk(dev: ?*const block.Device) void {
    disk = dev;
}

pub fn setNextFreeHint(value: u32) void {
    next_free_hint = value;
}

pub fn rootCluster() u32 {
    return fs.root_cluster;
}

pub fn clusterBytes() u32 {
    return fs.cluster_bytes;
}

pub fn loadNextFreeHint(boot: []const u8) ?u32 {
    const fsinfo_sector = bytes.readU16Le(boot, 0x42);
    if (fsinfo_sector == 0) return null;

    var sector: [512]u8 = undefined;
    readSector(fsinfo_sector, &sector) catch return null;
    if (bytes.readU32Le(&sector, 0) != 0x4161_5252) return null;
    if (bytes.readU32Le(&sector, 0x1E4) != 0x6141_7272) return null;

    const next = bytes.readU32Le(&sector, 0x1EC);
    if (next < 2 or next >= 0x0FFF_FFF0) return null;
    return next;
}

pub fn readSector(lba: u64, buf: []u8) FatError!void {
    const dev = try diskDevice();
    dev.readSectors(lba, buf) catch return FatError.IoError;
}

pub fn writeSector(lba: u64, buf: []const u8) FatError!void {
    const dev = try diskDevice();
    dev.writeSectors(lba, buf) catch return FatError.IoError;
}

pub fn readCluster(cluster: u32, buf: []u8) FatError!void {
    const first_sector = fs.data_start_sector + (cluster - 2) * fs.sectors_per_cluster;
    var i: u32 = 0;
    while (i < fs.sectors_per_cluster) : (i += 1) {
        const sector_buf = buf[@as(usize, i) * fs.bytes_per_sector ..][0..fs.bytes_per_sector];
        try readSector(first_sector + i, sector_buf);
    }
}

pub fn writeCluster(cluster: u32, buf: []const u8) FatError!void {
    const first_sector = fs.data_start_sector + (cluster - 2) * fs.sectors_per_cluster;
    var i: u32 = 0;
    while (i < fs.sectors_per_cluster) : (i += 1) {
        const sector_buf = buf[@as(usize, i) * fs.bytes_per_sector ..][0..fs.bytes_per_sector];
        try writeSector(first_sector + i, sector_buf);
    }
}

pub fn nextCluster(cluster: u32) FatError!u32 {
    const next = getFatEntry(cluster) catch return FatError.IoError;
    if (next < 2 or next >= 0x0FFF_FFF8) return FatError.IoError;
    return next;
}

pub fn nextClusterOrExtend(cluster: u32) FatError!u32 {
    const next = getFatEntry(cluster) catch return FatError.IoError;
    if (next >= 2 and next < 0x0FFFFFF8) return next;

    const new_cluster = try allocCluster();
    try setFatEntry(cluster, new_cluster);
    return new_cluster;
}

pub fn getFatEntry(cluster: u32) FatError!u32 {
    const fat_offset = @as(u64, cluster) * 4;
    const fat_sector = fs.fat_start_sector + @as(u32, @truncate(fat_offset / fs.bytes_per_sector));
    const fat_off = @as(usize, @truncate(fat_offset % fs.bytes_per_sector));

    var sector: [512]u8 = undefined;
    try readSector(fat_sector, &sector);
    return bytes.readU32Le(&sector, fat_off) & 0x0FFF_FFFF;
}

pub fn setFatEntry(cluster: u32, value: u32) FatError!void {
    const fat_offset = @as(u64, cluster) * 4;
    const fat_sector_base = fs.fat_start_sector + @as(u32, @truncate(fat_offset / fs.bytes_per_sector));
    const fat_off = @as(usize, @truncate(fat_offset % fs.bytes_per_sector));

    var fat_idx: u32 = 0;
    while (fat_idx < fs.num_fats) : (fat_idx += 1) {
        const fat_sector = fat_sector_base + fat_idx * fs.sectors_per_fat;
        var sector: [512]u8 = undefined;
        try readSector(fat_sector, &sector);
        const existing = bytes.readU32Le(&sector, fat_off);
        const merged = (existing & 0xF000_0000) | (value & 0x0FFF_FFFF);
        bytes.writeU32Le(&sector, fat_off, merged);
        try writeSector(fat_sector, &sector);
    }
}

pub fn allocCluster() FatError!u32 {
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

pub fn freeChain(start: u32) FatError!void {
    var cluster = start;
    var hops: u32 = 0;
    while (cluster >= 2 and cluster < 0x0FFFFFF8) : (hops += 1) {
        if (hops > 65536) return FatError.IoError;
        const next = getFatEntry(cluster) catch break;
        try setFatEntry(cluster, 0);
        cluster = next;
    }
}

pub fn writeDirEntryFields(off: usize, entry: Entry) void {
    const hi: u16 = @truncate(entry.start_cluster >> 16);
    const lo: u16 = @truncate(entry.start_cluster & 0xFFFF);
    bytes.writeU16Le(&cluster_buf, off + 20, hi);
    bytes.writeU16Le(&cluster_buf, off + 26, lo);
    bytes.writeU32Le(&cluster_buf, off + 28, entry.size);
    cluster_buf[off + 11] = entry.attr;
}

pub fn writeClusterFields(off: usize, cluster: u32) void {
    const hi: u16 = @truncate(cluster >> 16);
    const lo: u16 = @truncate(cluster & 0xFFFF);
    bytes.writeU16Le(&cluster_buf, off + 20, hi);
    bytes.writeU16Le(&cluster_buf, off + 26, lo);
}

pub fn entryFromRaw(raw: []const u8) Entry {
    const hi = bytes.readU16Le(raw, 20);
    const lo = bytes.readU16Le(raw, 26);
    return .{
        .start_cluster = (@as(u32, hi) << 16) | lo,
        .size = bytes.readU32Le(raw, 28),
        .attr = raw[11],
    };
}

fn maxDataCluster() u32 {
    const dev = diskDevice() catch return 2;
    const cap = dev.capacity();
    if (cap <= fs.data_start_sector) return 2;
    const data_sectors = cap - fs.data_start_sector;
    const clusters = data_sectors / fs.sectors_per_cluster;
    return @intCast(@min(clusters + 2, 0x0FFF_FFF0));
}

fn diskDevice() FatError!*const block.Device {
    return disk orelse block.default() orelse FatError.NotReady;
}
