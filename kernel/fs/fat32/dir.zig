const std = @import("std");
const abi_fs = @import("abi_fs");
const core = @import("core.zig");
const path = @import("path.zig");

pub const FatError = core.FatError;
pub const Entry = core.Entry;
pub const DirLoc = core.DirLoc;
pub const OpenResult = core.OpenResult;

pub fn lookup(path_str: []const u8) FatError!Entry {
    if (!core.isMounted()) return FatError.NotReady;

    var norm: [256]u8 = undefined;
    const clean = try path.normalizePath(path_str, &norm);

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

pub fn lookupParentCluster(clean: []const u8) FatError!u32 {
    if (path.lastIndexOf(clean, '/')) |slash| {
        if (slash == 0) return core.rootCluster();
        const parent = try lookup(clean[0..slash]);
        if (parent.attr & 0x10 == 0) return FatError.NotFound;
        return parent.start_cluster;
    }
    return core.rootCluster();
}

/// Open an existing directory for read-only iteration via getDents64.
pub fn openDirectory(path_str: []const u8) FatError!OpenResult {
    if (!core.isMounted()) return FatError.NotReady;

    const entry = try lookup(path_str);
    if (entry.attr & 0x10 == 0) return FatError.NotFile;
    return .{ .entry = entry, .loc = .{ .cluster = 0, .offset = 0 } };
}

/// Create a new directory (fails if it already exists).
pub fn createDirectory(path_str: []const u8) FatError!void {
    if (!core.isMounted()) return FatError.NotReady;

    var norm: [256]u8 = undefined;
    const clean = try path.normalizePath(path_str, &norm);
    if (clean.len == 0) return FatError.Exists;

    const parent_cluster = try lookupParentCluster(clean);
    const name = path.parentName(clean);

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

/// Rename a file or directory within the FAT volume (same or different parent).
pub fn renamePath(old_path: []const u8, new_path: []const u8) FatError!void {
    if (!core.isMounted()) return FatError.NotReady;

    var old_norm: [256]u8 = undefined;
    var new_norm: [256]u8 = undefined;
    const old_clean = try path.normalizePath(old_path, &old_norm);
    const new_clean = try path.normalizePath(new_path, &new_norm);
    if (old_clean.len == 0 or new_clean.len == 0) return FatError.IsDirectory;
    if (std.mem.eql(u8, old_clean, new_clean)) return;

    const old_parent = try lookupParentCluster(old_clean);
    const old_name = path.parentName(old_clean);
    const old = try findInDirectoryWithLoc(old_parent, old_name);

    const new_parent = try lookupParentCluster(new_clean);
    const new_name = path.parentName(new_clean);
    if (findInDirectoryWithLoc(new_parent, new_name)) |_| return FatError.Exists else |_| {}

    var name83: [11]u8 = undefined;
    try toShortName(new_name, &name83);

    if (old_parent == new_parent) {
        try writeDirEntry(old.loc, &name83, old.entry);
        return;
    }

    const new_loc = try findFreeDentSlot(new_parent);
    try writeDirEntry(new_loc, &name83, old.entry);

    try core.readCluster(old.loc.cluster, core.cluster_buf[0..core.clusterBytes()]);
    const off: usize = @intCast(old.loc.offset);
    if (off + 32 > core.clusterBytes()) return FatError.IoError;
    core.cluster_buf[off] = 0xE5;
    try core.writeCluster(old.loc.cluster, core.cluster_buf[0..core.clusterBytes()]);
}

/// Remove an empty directory: free its clusters and mark the directory entry deleted.
pub fn removeDirectory(path_str: []const u8) FatError!DirLoc {
    if (!core.isMounted()) return FatError.NotReady;

    var norm: [256]u8 = undefined;
    const clean = try path.normalizePath(path_str, &norm);
    if (clean.len == 0) return FatError.IsDirectory;

    const parent_cluster = try lookupParentCluster(clean);
    const name = path.parentName(clean);
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
        // End-of-chain is a normal directory terminator when the last cluster is full
        // (no 0x00 dent). Do not surface that as IoError or the listing is discarded.
        cluster = core.nextCluster(cluster) catch break;
    }
    skip.* = index;
    return written;
}

pub fn findInDirectoryWithLoc(dir_cluster: u32, name: []const u8) FatError!OpenResult {
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

pub fn patchDirEntry(loc: DirLoc, entry: Entry) FatError!void {
    try core.readCluster(loc.cluster, core.cluster_buf[0..core.clusterBytes()]);
    const off: usize = @intCast(loc.offset);
    if (off + 32 > core.clusterBytes()) return FatError.IoError;

    core.writeDirEntryFields(off, entry);
    try core.writeCluster(loc.cluster, core.cluster_buf[0..core.clusterBytes()]);
}

pub fn writeDirEntry(loc: DirLoc, name83: *const [11]u8, entry: Entry) FatError!void {
    try core.readCluster(loc.cluster, core.cluster_buf[0..core.clusterBytes()]);
    const off: usize = @intCast(loc.offset);
    if (off + 32 > core.clusterBytes()) return FatError.IoError;

    @memset(core.cluster_buf[off .. off + 32], 0);
    @memcpy(core.cluster_buf[off .. off + 11], name83);
    core.writeDirEntryFields(off, entry);
    try core.writeCluster(loc.cluster, core.cluster_buf[0..core.clusterBytes()]);
}

pub fn findFreeDentSlot(dir_cluster: u32) FatError!DirLoc {
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

pub fn toShortName(name: []const u8, out: *[11]u8) FatError!void {
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
