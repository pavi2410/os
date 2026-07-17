//! Read-only `/proc` pseudo filesystem (seq-style generate-on-read).

const filesystem = @import("filesystem.zig");

const proc_magic: u64 = 0x70726f63; // "proc"
const attr_dir: u8 = 0x10;
const attr_file: u8 = 0x20;

const Node = enum(u32) {
    root = 0,
};

var mounted: bool = false;

pub const ops: filesystem.Ops = .{
    .name = "procfs",
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
    .use_page_cache = false,
};

pub fn isReady() bool {
    return mounted;
}

fn fsMount() filesystem.Error!void {
    mounted = true;
}

fn toOpenFile(node: Node) filesystem.OpenFile {
    const is_dir = node == .root;
    return .{
        .id = .{ .a = @intFromEnum(node), .b = proc_magic },
        .start_cluster = @intFromEnum(node),
        .size = 0,
        .attr = if (is_dir) attr_dir else attr_file,
        .loc_cluster = @intFromEnum(node),
        .loc_offset = 0,
    };
}

fn nodeFromOpen(file: filesystem.OpenFile) filesystem.Error!Node {
    if (file.id.b != proc_magic) return filesystem.Error.BadHandle;
    if (file.id.a > @intFromEnum(Node.root)) return filesystem.Error.BadHandle;
    return @enumFromInt(file.id.a);
}

fn resolve(path: []const u8) filesystem.Error!Node {
    if (!mounted) return filesystem.Error.NotReady;
    if (path.len == 0 or path[0] != '/') return filesystem.Error.NotFound;
    if (path.len == 1) return .root;
    return filesystem.Error.NotFound;
}

fn fsOpen(path: []const u8, flags: filesystem.OpenFlags) filesystem.Error!filesystem.OpenFile {
    if (flags.write or flags.create or flags.truncate or flags.append) return filesystem.Error.ReadOnly;
    if (!flags.read) return filesystem.Error.InvalidWhence;
    const node = try resolve(path);
    return toOpenFile(node);
}

fn fsRead(file: filesystem.OpenFile, offset: u64, buf: []u8) filesystem.Error!usize {
    const node = try nodeFromOpen(file);
    if (node == .root) return filesystem.Error.IsDirectory;
    _ = offset;
    _ = buf;
    return 0;
}

fn fsWriteAt(_: *filesystem.OpenFile, _: u64, _: []const u8) filesystem.Error!usize {
    return filesystem.Error.ReadOnly;
}

fn fsStat(path: []const u8, out: *filesystem.Stat) filesystem.Error!void {
    const node = try resolve(path);
    out.* = .{};
    out.st_ino = @intFromEnum(node) + 1;
    out.st_mode = filesystem.S_IFDIR | 0o555;
    out.st_nlink = 1;
    out.st_size = 0;
}

fn fsGetdents64(file: filesystem.OpenFile, dir_skip: *usize, buf: []u8) filesystem.Error!usize {
    const node = try nodeFromOpen(file);
    if (node != .root) return filesystem.Error.NotFile;
    _ = buf;
    // Empty root until cpuinfo/iomem land.
    dir_skip.* = 0;
    return 0;
}

fn fsUnlink(_: []const u8) filesystem.Error!?filesystem.FileId {
    return filesystem.Error.ReadOnly;
}

fn fsMkdir(_: []const u8) filesystem.Error!void {
    return filesystem.Error.ReadOnly;
}

fn fsRmdir(_: []const u8) filesystem.Error!?filesystem.FileId {
    return filesystem.Error.ReadOnly;
}

/// Host tests / remount.
pub fn resetForTest() void {
    mounted = false;
}
