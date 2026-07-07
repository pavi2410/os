const core = @import("core.zig");
const path = @import("path.zig");
const dir = @import("dir.zig");

pub const FatError = core.FatError;
pub const Entry = core.Entry;
pub const DirLoc = core.DirLoc;
pub const OpenResult = core.OpenResult;

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
pub fn openFile(path_str: []const u8, truncate: bool) FatError!OpenResult {
    if (!core.isMounted()) return FatError.NotReady;

    var norm: [256]u8 = undefined;
    const clean = try path.normalizePath(path_str, &norm);
    if (clean.len == 0) return FatError.IsDirectory;

    const parent_cluster = try dir.lookupParentCluster(clean);
    const name = path.parentName(clean);
    var result = try dir.findInDirectoryWithLoc(parent_cluster, name);

    if (result.entry.attr & 0x10 != 0) return FatError.IsDirectory;
    if (truncate) try truncateFile(&result.entry, result.loc);
    return result;
}

/// Create a new file (fails if it already exists).
pub fn createFile(path_str: []const u8) FatError!OpenResult {
    if (!core.isMounted()) return FatError.NotReady;

    var norm: [256]u8 = undefined;
    const clean = try path.normalizePath(path_str, &norm);
    if (clean.len == 0) return FatError.IsDirectory;

    const parent_cluster = try dir.lookupParentCluster(clean);
    const name = path.parentName(clean);

    if (dir.findInDirectoryWithLoc(parent_cluster, name)) |_| return FatError.Exists else |_| {}

    var name83: [11]u8 = undefined;
    try dir.toShortName(name, &name83);

    const loc = try dir.findFreeDentSlot(parent_cluster);
    const cluster = try core.allocCluster();

    const entry: Entry = .{
        .start_cluster = cluster,
        .size = 0,
        .attr = 0x20, // archive
    };
    try dir.writeDirEntry(loc, &name83, entry);

    return .{ .entry = entry, .loc = loc };
}

pub fn writeAt(result: *OpenResult, offset: u64, buf: []const u8) FatError!usize {
    if (!core.isMounted()) return FatError.NotReady;
    if (result.entry.attr & 0x10 != 0) return FatError.IsDirectory;

    const n = try writeEntryData(&result.entry, offset, buf);
    try dir.patchDirEntry(result.loc, result.entry);
    return n;
}

/// Delete a regular file: free its clusters and mark the directory entry deleted.
pub fn unlinkFile(path_str: []const u8) FatError!DirLoc {
    if (!core.isMounted()) return FatError.NotReady;

    var norm: [256]u8 = undefined;
    const clean = try path.normalizePath(path_str, &norm);
    if (clean.len == 0) return FatError.IsDirectory;

    const parent_cluster = try dir.lookupParentCluster(clean);
    const name = path.parentName(clean);
    const result = try dir.findInDirectoryWithLoc(parent_cluster, name);

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
    try dir.patchDirEntry(loc, entry.*);
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
