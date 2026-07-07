const std = @import("std");
const abi_fs = @import("abi_fs");
const bytes = @import("common_bytes");
const block = @import("../drivers/block.zig");
const core = @import("fat32/core.zig");
const filesystem = @import("filesystem.zig");

pub const FatError = core.FatError;
pub const Entry = core.Entry;
pub const DirLoc = core.DirLoc;
pub const OpenResult = core.OpenResult;

pub const ops: filesystem.Ops = .{
    .name = "fat32",
    .mount = fsMount,
    .is_ready = core.isMounted,
    .open = fsOpen,
    .read = fsRead,
    .write_at = fsWriteAt,
    .stat = fsStat,
    .getdents64 = fsGetDents64,
    .unlink = fsUnlink,
    .mkdir = fsMkdir,
    .rmdir = fsRmdir,
};

pub fn mount() FatError!void {
    const dev = block.default() orelse return FatError.NotReady;
    if (!dev.isReady()) return FatError.NotReady;
    core.setDisk(dev);

    var boot: [512]u8 = undefined;
    try core.readSector(0, &boot);

    if (boot[510] != 0x55 or boot[511] != 0xAA) return FatError.InvalidBpb;
    const fs_type = boot[0x52 .. 0x52 + 8];
    if (!std.mem.eql(u8, fs_type, "FAT32   ") and !std.mem.eql(u8, fs_type, "FAT16   ") and !std.mem.eql(u8, fs_type, "FAT     ")) {
        return FatError.InvalidBpb;
    }

    const bytes_per_sector = bytes.readU16Le(&boot, 0x0B);
    const sectors_per_cluster = boot[0x0D];
    const reserved_sectors = bytes.readU16Le(&boot, 0x0E);
    const num_fats = boot[0x10];
    const sectors_per_fat = bytes.readU32Le(&boot, 0x24);
    const root_cluster = bytes.readU32Le(&boot, 0x2C);

    if (bytes_per_sector != dev.sectorSize()) return FatError.InvalidBpb;
    if (sectors_per_cluster == 0 or num_fats == 0) return FatError.InvalidBpb;

    const cluster_bytes = @as(u32, sectors_per_cluster) * bytes_per_sector;
    if (cluster_bytes > core.cluster_buf.len) return FatError.InvalidBpb;

    core.setMountParams(.{
        .bytes_per_sector = bytes_per_sector,
        .sectors_per_cluster = sectors_per_cluster,
        .reserved_sectors = reserved_sectors,
        .num_fats = num_fats,
        .sectors_per_fat = sectors_per_fat,
        .root_cluster = root_cluster,
        .fat_start_sector = reserved_sectors,
        .data_start_sector = reserved_sectors + @as(u32, num_fats) * sectors_per_fat,
        .cluster_bytes = cluster_bytes,
    });
    core.setNextFreeHint(core.loadNextFreeHint(&boot) orelse 2);
    core.setMounted(true);
}

pub fn isMounted() bool {
    return core.isMounted();
}

pub fn lookup(path: []const u8) FatError!Entry {
    if (!core.isMounted()) return FatError.NotReady;

    var norm: [256]u8 = undefined;
    const clean = try normalizePath(path, &norm);

    if (clean.len == 0) {
        return .{
            .start_cluster = core.rootCluster(),
            .size = 0,
            .attr = 0x10,
        };
    }

    var cluster = core.rootCluster();
    var component: []const u8 = clean;
    while (true) {
        const slash = std.mem.indexOfScalar(u8, component, '/');
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
    if (!core.isMounted()) return FatError.NotReady;
    if (entry.attr & 0x10 != 0) return FatError.IsDirectory;
    if (offset >= entry.size) return 0;

    const to_read = @min(buf.len, entry.size - @as(u32, @truncate(offset)));
    var copied: usize = 0;
    var file_off: u32 = @truncate(offset);
    var cluster = entry.start_cluster;

    if (file_off > 0) {
        const skip_clusters = file_off / core.clusterBytes();
        var i: u32 = 0;
        while (i < skip_clusters) : (i += 1) {
            cluster = try core.nextCluster(cluster);
        }
        file_off %= core.clusterBytes();
    }

    while (copied < to_read) {
        try core.readCluster(cluster, core.cluster_buf[0..core.clusterBytes()]);
        const chunk_start = file_off;
        const chunk_len = @min(to_read - copied, core.clusterBytes() - chunk_start);
        @memcpy(buf[copied .. copied + chunk_len], core.cluster_buf[chunk_start .. chunk_start + chunk_len]);
        copied += chunk_len;
        file_off = 0;
        if (copied < to_read) cluster = try core.nextCluster(cluster);
    }

    return copied;
}

/// Open an existing file for read/write, optionally truncating it.
pub fn openFile(path: []const u8, truncate: bool) FatError!OpenResult {
    if (!core.isMounted()) return FatError.NotReady;

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
    if (!core.isMounted()) return FatError.NotReady;

    var norm: [256]u8 = undefined;
    const clean = try normalizePath(path, &norm);
    if (clean.len == 0) return FatError.IsDirectory;

    const parent_cluster = try lookupParentCluster(clean);
    const name = parentName(clean);

    if (findInDirectoryWithLoc(parent_cluster, name)) |_| return FatError.Exists else |_| {}

    var name83: [11]u8 = undefined;
    try toShortName(name, &name83);

    const loc = try findFreeDentSlot(parent_cluster);
    const cluster = try core.allocCluster();

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
    if (!core.isMounted()) return FatError.NotReady;

    var norm: [256]u8 = undefined;
    const clean = try normalizePath(path, &norm);
    if (clean.len == 0) return FatError.Exists;

    const parent_cluster = try lookupParentCluster(clean);
    const name = parentName(clean);

    if (findInDirectoryWithLoc(parent_cluster, name)) |_| return FatError.Exists else |_| {}

    var name83: [11]u8 = undefined;
    try toShortName(name, &name83);

    const loc = try findFreeDentSlot(parent_cluster);
    const cluster = try core.allocCluster();
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
    if (!core.isMounted()) return FatError.NotReady;

    var norm: [256]u8 = undefined;
    const clean = try normalizePath(path, &norm);
    if (clean.len == 0) return FatError.IsDirectory;

    const parent_cluster = try lookupParentCluster(clean);
    const name = parentName(clean);
    const result = try findInDirectoryWithLoc(parent_cluster, name);

    if (result.entry.attr & 0x10 == 0) return FatError.NotFile;
    if (!try directoryIsEmpty(result.entry.start_cluster)) return FatError.NotEmpty;
    if (result.entry.start_cluster >= 2) try core.freeChain(result.entry.start_cluster);

    try core.readCluster(result.loc.cluster, core.cluster_buf[0..core.clusterBytes()]);
    const off: usize = @intCast(result.loc.offset);
    if (off + 32 > core.clusterBytes()) return FatError.IoError;
    core.cluster_buf[off] = 0xE5;
    try core.writeCluster(result.loc.cluster, core.cluster_buf[0..core.clusterBytes()]);
    return result.loc;
}

fn directoryIsEmpty(dir_cluster: u32) FatError!bool {
    var cluster = dir_cluster;
    while (cluster >= 2 and cluster < 0x0FFFFFF8) {
        try core.readCluster(cluster, core.cluster_buf[0..core.clusterBytes()]);
        var off: usize = 0;
        while (off + 32 <= core.clusterBytes()) {
            const entry = core.cluster_buf[off .. off + 32];
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
        cluster = core.nextCluster(cluster) catch return true;
    }
    return true;
}

fn initDirectoryCluster(cluster: u32, parent_cluster: u32) FatError!void {
    @memset(core.cluster_buf[0..core.clusterBytes()], 0);
    writeDotEntry(0, cluster);
    writeDotEntry(32, parent_cluster);
    try core.writeCluster(cluster, core.cluster_buf[0..core.clusterBytes()]);
}

fn writeDotEntry(off: usize, target_cluster: u32) void {
    if (off + 32 > core.clusterBytes()) return;
    if (off == 0) {
        core.cluster_buf[off] = '.';
    } else {
        core.cluster_buf[off] = '.';
        core.cluster_buf[off + 1] = '.';
    }
    core.cluster_buf[off + 11] = 0x10;
    core.writeClusterFields(off, target_cluster);
}

pub fn writeAt(result: *OpenResult, offset: u64, buf: []const u8) FatError!usize {
    if (!core.isMounted()) return FatError.NotReady;
    if (result.entry.attr & 0x10 != 0) return FatError.IsDirectory;

    const n = try writeEntryData(&result.entry, offset, buf);
    try patchDirEntry(result.loc, result.entry);
    return n;
}

/// Delete a regular file: free its clusters and mark the directory entry deleted.
pub fn unlinkFile(path: []const u8) FatError!DirLoc {
    if (!core.isMounted()) return FatError.NotReady;

    var norm: [256]u8 = undefined;
    const clean = try normalizePath(path, &norm);
    if (clean.len == 0) return FatError.IsDirectory;

    const parent_cluster = try lookupParentCluster(clean);
    const name = parentName(clean);
    const result = try findInDirectoryWithLoc(parent_cluster, name);

    if (result.entry.attr & 0x10 != 0) return FatError.IsDirectory;
    if (result.entry.start_cluster >= 2) try core.freeChain(result.entry.start_cluster);

    try core.readCluster(result.loc.cluster, core.cluster_buf[0..core.clusterBytes()]);
    const off: usize = @intCast(result.loc.offset);
    if (off + 32 > core.clusterBytes()) return FatError.IoError;
    core.cluster_buf[off] = 0xE5;
    try core.writeCluster(result.loc.cluster, core.cluster_buf[0..core.clusterBytes()]);
    return result.loc;
}

fn truncateFile(entry: *Entry, loc: DirLoc) FatError!void {
    if (entry.start_cluster >= 2) try core.freeChain(entry.start_cluster);
    entry.start_cluster = try core.allocCluster();
    entry.size = 0;
    try patchDirEntry(loc, entry.*);
}

fn writeEntryData(entry: *Entry, offset: u64, buf: []const u8) FatError!usize {
    if (buf.len == 0) return 0;

    var written: usize = 0;
    var file_off: u32 = @truncate(offset);
    var cluster = entry.start_cluster;

    if (file_off > 0) {
        const skip_clusters = file_off / core.clusterBytes();
        var i: u32 = 0;
        while (i < skip_clusters) : (i += 1) {
            cluster = try core.nextCluster(cluster);
        }
        file_off %= core.clusterBytes();
    }

    while (written < buf.len) {
        try core.readCluster(cluster, core.cluster_buf[0..core.clusterBytes()]);
        const chunk_start = file_off;
        const chunk_len = @min(buf.len - written, core.clusterBytes() - chunk_start);
        @memcpy(core.cluster_buf[chunk_start .. chunk_start + chunk_len], buf[written .. written + chunk_len]);
        try core.writeCluster(cluster, core.cluster_buf[0..core.clusterBytes()]);

        written += chunk_len;
        file_off = 0;

        if (written < buf.len) {
            cluster = try core.nextClusterOrExtend(cluster);
        }
    }

    const end_off = offset + written;
    if (end_off > entry.size) entry.size = @truncate(end_off);
    return written;
}


fn patchDirEntry(loc: DirLoc, entry: Entry) FatError!void {
    try core.readCluster(loc.cluster, core.cluster_buf[0..core.clusterBytes()]);
    const off: usize = @intCast(loc.offset);
    if (off + 32 > core.clusterBytes()) return FatError.IoError;

    core.writeDirEntryFields(off, entry);
    try core.writeCluster(loc.cluster, core.cluster_buf[0..core.clusterBytes()]);
}

fn writeDirEntry(loc: DirLoc, name83: *const [11]u8, entry: Entry) FatError!void {
    try core.readCluster(loc.cluster, core.cluster_buf[0..core.clusterBytes()]);
    const off: usize = @intCast(loc.offset);
    if (off + 32 > core.clusterBytes()) return FatError.IoError;

    @memset(core.cluster_buf[off .. off + 32], 0);
    @memcpy(core.cluster_buf[off .. off + 11], name83);
    core.writeDirEntryFields(off, entry);
    try core.writeCluster(loc.cluster, core.cluster_buf[0..core.clusterBytes()]);
}

fn findFreeDentSlot(dir_cluster: u32) FatError!DirLoc {
    var cluster = dir_cluster;
    var last_cluster = dir_cluster;

    while (cluster >= 2 and cluster < 0x0FFFFFF8) {
        last_cluster = cluster;
        try core.readCluster(cluster, core.cluster_buf[0..core.clusterBytes()]);
        var off: usize = 0;
        while (off + 32 <= core.clusterBytes()) {
            const entry = core.cluster_buf[off .. off + 32];
            if (entry[0] == 0x00 or entry[0] == 0xE5) {
                return .{ .cluster = cluster, .offset = @intCast(off) };
            }
            off += 32;
        }
        cluster = core.getFatEntry(cluster) catch return FatError.IoError;
        if (cluster >= 2 and cluster < 0x0FFFFFF8) continue;
        break;
    }

    const new_cluster = try core.allocCluster();
    try core.setFatEntry(last_cluster, new_cluster);
    @memset(core.cluster_buf[0..core.clusterBytes()], 0);
    try core.writeCluster(new_cluster, core.cluster_buf[0..core.clusterBytes()]);
    return .{ .cluster = new_cluster, .offset = 0 };
}





fn lookupParentCluster(clean: []const u8) FatError!u32 {
    if (lastIndexOf(clean, '/')) |slash| {
        if (slash == 0) return core.rootCluster();
        const parent = try lookup(clean[0..slash]);
        if (parent.attr & 0x10 == 0) return FatError.NotFound;
        return parent.start_cluster;
    }
    return core.rootCluster();
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
        try core.readCluster(cluster, core.cluster_buf[0..core.clusterBytes()]);
        var off: usize = 0;
        while (off + 32 <= core.clusterBytes()) {
            const entry = core.cluster_buf[off .. off + 32];
            if (entry[0] == 0) return FatError.NotFound;
            if (entry[0] == 0xE5 or entry[0] == 0x2E) {
                off += 32;
                continue;
            }
            if (entry[11] == 0x0F) {
                off += 32;
                continue;
            }
            if (std.mem.eql(u8, entry[0..11], &name83)) {
                return .{
                    .entry = core.entryFromRaw(entry),
                    .loc = .{ .cluster = cluster, .offset = @intCast(off) },
                };
            }
            off += 32;
        }
        cluster = core.nextCluster(cluster) catch return FatError.NotFound;
    }
    return FatError.NotFound;
}

/// Open an existing directory for read-only iteration via getDents64.
pub fn openDirectory(path: []const u8) FatError!OpenResult {
    if (!core.isMounted()) return FatError.NotReady;

    const entry = try lookup(path);
    if (entry.attr & 0x10 == 0) return FatError.NotFile;
    return .{ .entry = entry, .loc = .{ .cluster = 0, .offset = 0 } };
}

const dirent_name_off = abi_fs.dirent64_name_offset;

/// Fill `out` with linux_dirent64 records from `dir_cluster`, skipping the first `skip` entries.
pub fn getDents64(dir_cluster: u32, skip: *usize, out: []u8) FatError!usize {
    if (!core.isMounted()) return FatError.NotReady;
    if (out.len < dirent_name_off + 2) return FatError.BufferTooSmall;

    var written: usize = 0;
    var index: usize = 0;
    var next_off: i64 = 0;
    var cluster = dir_cluster;
    var name_buf: [13]u8 = undefined;

    while (cluster >= 2 and cluster < 0x0FFFFFF8) {
        try core.readCluster(cluster, core.cluster_buf[0..core.clusterBytes()]);
        var off: usize = 0;
        while (off + 32 <= core.clusterBytes()) {
            const entry = core.cluster_buf[off .. off + 32];
            if (entry[0] == 0) {
                skip.* = index;
                return written;
            }
            if (entry[0] == 0xE5 or entry[0] == 0x2E) {
                off += 32;
                continue;
            }
            if (entry[11] == 0x0F) {
                off += 32;
                continue;
            }
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

            if (index < skip.*) {
                index += 1;
                off += 32;
                continue;
            }

            const reclen = abi_fs.dirent64Reclen(name.len);
            if (written + reclen > out.len) {
                if (written == 0) return FatError.BufferTooSmall;
                skip.* = index;
                return written;
            }

            const rec = out[written .. written + reclen];
            abi_fs.writeDirent64(
                rec,
                (@as(u64, cluster) << 16) | @as(u64, off),
                next_off,
                if (entry[11] & 0x10 != 0) abi_fs.DT_DIR else abi_fs.DT_REG,
                name,
            );

            written += reclen;
            next_off += 1;
            index += 1;
            off += 32;
        }
        cluster = try core.nextCluster(cluster);
    }
    skip.* = index;
    return written;
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
        try core.readCluster(cluster, core.cluster_buf[0..core.clusterBytes()]);
        var off: usize = 0;
        while (off + 32 <= core.clusterBytes()) {
            const entry = core.cluster_buf[off .. off + 32];
            if (entry[0] == 0) return FatError.NotFound;
            if (entry[0] == 0xE5 or entry[0] == 0x2E) {
                off += 32;
                continue;
            }
            if (entry[11] == 0x0F) {
                off += 32;
                continue;
            }
            if (std.mem.eql(u8, entry[0..11], &name83)) {
                return core.entryFromRaw(entry);
            }
            off += 32;
        }
        cluster = core.nextCluster(cluster) catch return FatError.NotFound;
    }
    return FatError.NotFound;
}


fn fsMount() filesystem.Error!void {
    mount() catch |err| return fsError(err);
}

fn fsOpen(path: []const u8, flags: filesystem.OpenFlags) filesystem.Error!filesystem.OpenFile {
    const opened: OpenResult = blk: {
        if (lookup(path)) |entry| {
            if (entry.attr & 0x10 != 0) {
                if (flags.write or flags.create or flags.truncate) return filesystem.Error.IsDirectory;
                if (!flags.read) return filesystem.Error.IsDirectory;
                break :blk openDirectory(path) catch |err| return fsError(err);
            }
            break :blk openFile(path, flags.truncate) catch |err| return fsError(err);
        } else |_| {
            if (!flags.create) return filesystem.Error.NotFound;
            break :blk createFile(path) catch |err| return fsError(err);
        }
    };
    return toFsFile(opened);
}

fn fsRead(file: filesystem.OpenFile, offset: u64, buf: []u8) filesystem.Error!usize {
    return read(fromFsFile(file).entry, offset, buf) catch |err| return fsError(err);
}

fn fsWriteAt(file: *filesystem.OpenFile, offset: u64, buf: []const u8) filesystem.Error!usize {
    var opened = fromFsFile(file.*);
    const n = writeAt(&opened, offset, buf) catch |err| return fsError(err);
    file.* = toFsFile(opened);
    return n;
}

fn fsStat(path: []const u8, out: *filesystem.Stat) filesystem.Error!void {
    const entry = lookup(path) catch |err| return fsError(err);
    out.* = .{};
    out.st_mode = if (entry.attr & 0x10 != 0) filesystem.S_IFDIR | 0o755 else filesystem.S_IFREG | 0o644;
    out.st_size = @intCast(entry.size);
}

fn fsGetDents64(file: filesystem.OpenFile, dir_skip: *usize, buf: []u8) filesystem.Error!usize {
    return getDents64(file.start_cluster, dir_skip, buf) catch |err| return fsError(err);
}

fn fsUnlink(path: []const u8) filesystem.Error!?filesystem.FileId {
    const loc = unlinkFile(path) catch |err| return fsError(err);
    return fileId(loc);
}

fn fsMkdir(path: []const u8) filesystem.Error!void {
    createDirectory(path) catch |err| return fsError(err);
}

fn fsRmdir(path: []const u8) filesystem.Error!?filesystem.FileId {
    const loc = removeDirectory(path) catch |err| return fsError(err);
    return fileId(loc);
}

fn toFsFile(opened: OpenResult) filesystem.OpenFile {
    return .{
        .id = fileId(opened.loc),
        .start_cluster = opened.entry.start_cluster,
        .size = opened.entry.size,
        .attr = opened.entry.attr,
        .loc_cluster = opened.loc.cluster,
        .loc_offset = opened.loc.offset,
    };
}

fn fromFsFile(file: filesystem.OpenFile) OpenResult {
    return .{
        .entry = .{
            .start_cluster = file.start_cluster,
            .size = file.size,
            .attr = file.attr,
        },
        .loc = .{
            .cluster = file.loc_cluster,
            .offset = file.loc_offset,
        },
    };
}

fn fileId(loc: DirLoc) filesystem.FileId {
    return .{ .a = loc.cluster, .b = loc.offset };
}

fn fsError(err: FatError) filesystem.Error {
    return switch (err) {
        FatError.NotReady => filesystem.Error.NotReady,
        FatError.InvalidBpb => filesystem.Error.InvalidBpb,
        FatError.NotFound => filesystem.Error.NotFound,
        FatError.NotFile => filesystem.Error.NotFile,
        FatError.IsDirectory => filesystem.Error.IsDirectory,
        FatError.IoError => filesystem.Error.IoError,
        FatError.NameTooLong => filesystem.Error.NameTooLong,
        FatError.PathTooLong => filesystem.Error.PathTooLong,
        FatError.BufferTooSmall => filesystem.Error.BufferTooSmall,
        FatError.Exists => filesystem.Error.Exists,
        FatError.NoSpace => filesystem.Error.NoSpace,
        FatError.NotEmpty => filesystem.Error.NotEmpty,
    };
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
        if (std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return FatError.NotFound;
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

    const dot = std.mem.indexOfScalar(u8, name, '.');
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
