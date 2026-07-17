const abi_fs = @import("abi_fs");
const filesystem = @import("filesystem.zig");
const std = @import("std");

pub const max_nodes = 128;
pub const max_name_len = 64;
pub const max_data_bytes = 256 * 1024;

const tmpfs_id_magic: u64 = 0x746D7066; // "tmpf"
const attr_dir: u8 = 0x10;
const attr_file: u8 = 0x20;

const NodeKind = enum { dir, file };

const Node = struct {
    in_use: bool = false,
    kind: NodeKind = .file,
    parent: u16 = 0,
    name_len: u8 = 0,
    name: [max_name_len]u8 = undefined,
    mode: u16 = 0o644,
    ino: u64 = 0,
    /// File payload offset/length in `data_pool` (unused for directories).
    data_off: u32 = 0,
    data_len: u32 = 0,
    data_cap: u32 = 0,
};

var nodes: [max_nodes]Node = undefined;
var data_pool: [max_data_bytes]u8 = undefined;
var data_used: u32 = 0;
var next_ino: u64 = 1;
var mounted: bool = false;

pub const ops: filesystem.Ops = .{
    .name = "tmpfs",
    .mount = fsMount,
    .is_ready = isReady,
    .open = fsOpen,
    .read = fsRead,
    .write_at = fsWriteAt,
    .stat = fsStat,
    .getdents64 = fsGetdents64,
    .unlink = fsUnlink,
    .mkdir = fsMkdir,
    .rmdir = fsRmdir,
};

pub fn isReady() bool {
    return mounted;
}

fn fsMount() filesystem.Error!void {
    @memset(std.mem.asBytes(&nodes), 0);
    data_used = 0;
    next_ino = 1;
    nodes[0] = .{
        .in_use = true,
        .kind = .dir,
        .parent = 0,
        .name_len = 1,
        .mode = 0o755,
        .ino = allocIno(),
    };
    nodes[0].name[0] = '/';
    mounted = true;
}

fn allocIno() u64 {
    const id = next_ino;
    next_ino += 1;
    return id;
}

fn allocNode() filesystem.Error!u16 {
    var i: u16 = 1;
    while (i < max_nodes) : (i += 1) {
        if (!nodes[i].in_use) {
            nodes[i] = .{ .in_use = true, .ino = allocIno() };
            return i;
        }
    }
    return filesystem.Error.NoSpace;
}

fn freeNode(idx: u16) void {
    nodes[idx] = .{};
}

fn nameEql(node: *const Node, name: []const u8) bool {
    if (node.name_len != name.len) return false;
    return std.mem.eql(u8, node.name[0..node.name_len], name);
}

fn setName(node: *Node, name: []const u8) filesystem.Error!void {
    if (name.len == 0 or name.len > max_name_len) return filesystem.Error.NameTooLong;
    if (std.mem.indexOfScalar(u8, name, '/') != null) return filesystem.Error.InvalidWhence;
    @memcpy(node.name[0..name.len], name);
    node.name_len = @intCast(name.len);
}

fn findChild(parent: u16, name: []const u8) ?u16 {
    var i: u16 = 1;
    while (i < max_nodes) : (i += 1) {
        if (!nodes[i].in_use) continue;
        if (nodes[i].parent != parent) continue;
        if (nameEql(&nodes[i], name)) return i;
    }
    return null;
}

fn dirHasChildren(parent: u16) bool {
    var i: u16 = 1;
    while (i < max_nodes) : (i += 1) {
        if (nodes[i].in_use and nodes[i].parent == parent) return true;
    }
    return false;
}

const WalkResult = struct {
    parent: u16,
    idx: ?u16,
    name: []const u8,
};

/// Walk `path` (absolute within the tmpfs). For the final component, returns
/// parent + optional existing idx + final name. Intermediate components must be directories.
fn walk(path: []const u8) filesystem.Error!WalkResult {
    if (!mounted) return filesystem.Error.NotReady;
    if (path.len == 0 or path[0] != '/') return filesystem.Error.NotFound;
    if (path.len == 1) return .{ .parent = 0, .idx = 0, .name = "/" };

    var parent: u16 = 0;
    var start: usize = 1;
    while (start < path.len) {
        var end = start;
        while (end < path.len and path[end] != '/') : (end += 1) {}
        const name = path[start..end];
        if (name.len == 0) return filesystem.Error.NotFound;
        const at_final = end >= path.len;
        if (at_final) {
            return .{ .parent = parent, .idx = findChild(parent, name), .name = name };
        }
        const child = findChild(parent, name) orelse return filesystem.Error.NotFound;
        if (nodes[child].kind != .dir) return filesystem.Error.NotFile;
        parent = child;
        start = end + 1;
    }
    return filesystem.Error.NotFound;
}

fn toOpenFile(idx: u16) filesystem.OpenFile {
    const n = &nodes[idx];
    return .{
        .id = .{ .a = n.ino, .b = tmpfs_id_magic },
        .start_cluster = idx,
        .size = if (n.kind == .file) n.data_len else 0,
        .attr = if (n.kind == .dir) attr_dir else attr_file,
        .loc_cluster = idx,
        .loc_offset = 0,
    };
}

fn nodeFromOpen(file: filesystem.OpenFile) filesystem.Error!u16 {
    if (file.id.b != tmpfs_id_magic) return filesystem.Error.BadHandle;
    const idx: u16 = @intCast(file.start_cluster);
    if (idx >= max_nodes or !nodes[idx].in_use) return filesystem.Error.BadHandle;
    return idx;
}

fn createFileNode(parent: u16, name: []const u8) filesystem.Error!u16 {
    const idx = try allocNode();
    errdefer freeNode(idx);
    try setName(&nodes[idx], name);
    nodes[idx].kind = .file;
    nodes[idx].parent = parent;
    nodes[idx].mode = 0o666;
    nodes[idx].data_off = 0;
    nodes[idx].data_len = 0;
    nodes[idx].data_cap = 0;
    return idx;
}

fn createDirNode(parent: u16, name: []const u8) filesystem.Error!u16 {
    const idx = try allocNode();
    errdefer freeNode(idx);
    try setName(&nodes[idx], name);
    nodes[idx].kind = .dir;
    nodes[idx].parent = parent;
    nodes[idx].mode = 0o777;
    return idx;
}

fn ensureCapacity(idx: u16, need: u32) filesystem.Error!void {
    var n = &nodes[idx];
    if (need <= n.data_cap) return;
    const grow = if (n.data_cap == 0) @max(need, 64) else @max(need, n.data_cap * 2);
    if (data_used + grow > max_data_bytes) return filesystem.Error.NoSpace;
    const new_off = data_used;
    if (n.data_cap > 0 and n.data_len > 0) {
        @memcpy(data_pool[new_off .. new_off + n.data_len], data_pool[n.data_off .. n.data_off + n.data_len]);
    }
    n.data_off = new_off;
    n.data_cap = grow;
    data_used += grow;
}

fn fsOpen(path: []const u8, flags: filesystem.OpenFlags) filesystem.Error!filesystem.OpenFile {
    const w = try walk(path);
    if (w.idx) |idx| {
        const n = &nodes[idx];
        if (n.kind == .dir) {
            if (flags.write or flags.create or flags.truncate) return filesystem.Error.IsDirectory;
            if (!flags.read) return filesystem.Error.IsDirectory;
            return toOpenFile(idx);
        }
        if (flags.truncate) {
            n.data_len = 0;
        }
        return toOpenFile(idx);
    }
    if (!flags.create) return filesystem.Error.NotFound;
    if (std.mem.eql(u8, w.name, "/")) return filesystem.Error.Exists;
    const idx = try createFileNode(w.parent, w.name);
    return toOpenFile(idx);
}

fn fsRead(file: filesystem.OpenFile, offset: u64, buf: []u8) filesystem.Error!usize {
    const idx = try nodeFromOpen(file);
    const n = &nodes[idx];
    if (n.kind != .file) return filesystem.Error.IsDirectory;
    if (offset >= n.data_len or buf.len == 0) return 0;
    const off: u32 = @intCast(offset);
    const avail = n.data_len - off;
    const take = @min(buf.len, avail);
    @memcpy(buf[0..take], data_pool[n.data_off + off .. n.data_off + off + take]);
    return take;
}

fn fsWriteAt(file: *filesystem.OpenFile, offset: u64, buf: []const u8) filesystem.Error!usize {
    const idx = try nodeFromOpen(file.*);
    const n = &nodes[idx];
    if (n.kind != .file) return filesystem.Error.IsDirectory;
    if (buf.len == 0) return 0;
    const end = offset + buf.len;
    if (end > std.math.maxInt(u32)) return filesystem.Error.NoSpace;
    try ensureCapacity(idx, @intCast(end));
    const off: u32 = @intCast(offset);
    if (off > n.data_len) {
        @memset(data_pool[n.data_off + n.data_len .. n.data_off + off], 0);
    }
    @memcpy(data_pool[n.data_off + off .. n.data_off + off + buf.len], buf);
    if (end > n.data_len) n.data_len = @intCast(end);
    file.size = n.data_len;
    return buf.len;
}

fn fsStat(path: []const u8, out: *filesystem.Stat) filesystem.Error!void {
    const w = try walk(path);
    const idx = w.idx orelse return filesystem.Error.NotFound;
    const n = &nodes[idx];
    out.* = .{};
    out.st_ino = n.ino;
    out.st_mode = if (n.kind == .dir) filesystem.S_IFDIR | n.mode else filesystem.S_IFREG | n.mode;
    out.st_size = if (n.kind == .file) @intCast(n.data_len) else 0;
    out.st_nlink = 1;
}

fn fsGetdents64(file: filesystem.OpenFile, dir_skip: *usize, buf: []u8) filesystem.Error!usize {
    const idx = try nodeFromOpen(file);
    if (nodes[idx].kind != .dir) return filesystem.Error.NotFile;

    var children: [max_nodes]u16 = undefined;
    var count: usize = 0;
    var i: u16 = 1;
    while (i < max_nodes) : (i += 1) {
        if (nodes[i].in_use and nodes[i].parent == idx) {
            children[count] = i;
            count += 1;
        }
    }

    if (dir_skip.* >= count) return 0;
    var written: usize = 0;
    var index = dir_skip.*;
    while (index < count) : (index += 1) {
        const child = &nodes[children[index]];
        const name = child.name[0..child.name_len];
        const reclen = abi_fs.dirent64Reclen(name.len);
        if (written + reclen > buf.len) {
            if (written == 0) return filesystem.Error.BufferTooSmall;
            dir_skip.* = index;
            return written;
        }
        const dtype: u8 = if (child.kind == .dir) abi_fs.DT_DIR else abi_fs.DT_REG;
        abi_fs.writeDirent64(buf[written .. written + reclen], child.ino, @intCast(index + 1), dtype, name);
        written += reclen;
    }
    dir_skip.* = count;
    return written;
}

fn fsUnlink(path: []const u8) filesystem.Error!?filesystem.FileId {
    const w = try walk(path);
    const idx = w.idx orelse return filesystem.Error.NotFound;
    if (nodes[idx].kind != .file) return filesystem.Error.IsDirectory;
    const id = toOpenFile(idx).id;
    freeNode(idx);
    return id;
}

fn fsMkdir(path: []const u8) filesystem.Error!void {
    const w = try walk(path);
    if (w.idx != null) return filesystem.Error.Exists;
    if (std.mem.eql(u8, w.name, "/")) return filesystem.Error.Exists;
    _ = try createDirNode(w.parent, w.name);
}

fn fsRmdir(path: []const u8) filesystem.Error!?filesystem.FileId {
    const w = try walk(path);
    const idx = w.idx orelse return filesystem.Error.NotFound;
    if (idx == 0) return filesystem.Error.ReadOnly;
    if (nodes[idx].kind != .dir) return filesystem.Error.NotFile;
    if (dirHasChildren(idx)) return filesystem.Error.NotEmpty;
    const id = toOpenFile(idx).id;
    freeNode(idx);
    return id;
}

/// Reset state (host tests / remount / umount).
pub fn resetForTest() void {
    mounted = false;
    data_used = 0;
    next_ino = 1;
    @memset(std.mem.asBytes(&nodes), 0);
}

pub fn unmount() void {
    resetForTest();
}
