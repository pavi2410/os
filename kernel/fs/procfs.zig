//! Read-only `/proc` pseudo filesystem (seq-style generate-on-read).
//!
//! Files:
//! - `/proc/cpuinfo` — CPUID snapshot (Linux-ish keys; extras: apic_id, ioapic_count)
//! - `/proc/iomem` — physical memory map (`start-end : type`)

const abi_fs = @import("abi_fs");
const filesystem = @import("filesystem.zig");
const seq = @import("seq.zig");
const hw_format = @import("../hw/format.zig");
const hw_info = @import("../hw/info.zig");
const std = @import("std");

const proc_magic: u64 = 0x70726f63; // "proc"
const attr_dir: u8 = 0x10;
const attr_file: u8 = 0x20;

const Node = enum(u32) {
    root = 0,
    cpuinfo = 1,
    iomem = 2,
};

const root_entries = [_]struct { name: []const u8, node: Node }{
    .{ .name = "cpuinfo", .node = .cpuinfo },
    .{ .name = "iomem", .node = .iomem },
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
    if (file.id.a > @intFromEnum(Node.iomem)) return filesystem.Error.BadHandle;
    return @enumFromInt(file.id.a);
}

fn resolve(path: []const u8) filesystem.Error!Node {
    if (!mounted) return filesystem.Error.NotReady;
    if (path.len == 0 or path[0] != '/') return filesystem.Error.NotFound;
    if (path.len == 1) return .root;

    var start: usize = 1;
    while (start < path.len and path[start] == '/') : (start += 1) {}
    if (start >= path.len) return .root;

    var end = start;
    while (end < path.len and path[end] != '/') : (end += 1) {}
    const name = path[start..end];
    if (end < path.len) {
        // No nested paths under files.
        var rest = end + 1;
        while (rest < path.len and path[rest] == '/') : (rest += 1) {}
        if (rest < path.len) return filesystem.Error.NotFound;
    }

    for (root_entries) |e| {
        if (std.mem.eql(u8, e.name, name)) return e.node;
    }
    return filesystem.Error.NotFound;
}

fn fsOpen(path: []const u8, flags: filesystem.OpenFlags) filesystem.Error!filesystem.OpenFile {
    if (flags.write or flags.create or flags.truncate or flags.append) return filesystem.Error.ReadOnly;
    if (!flags.read) return filesystem.Error.InvalidWhence;
    const node = try resolve(path);
    return toOpenFile(node);
}

fn render(node: Node, dest: []u8) usize {
    return switch (node) {
        .root => 0,
        .cpuinfo => blk: {
            var info: hw_info.CpuInfo = undefined;
            hw_info.fillCpuInfo(&info);
            break :blk hw_format.formatCpuinfo(&info, dest);
        },
        .iomem => blk: {
            var regions: [256]hw_info.MemRegionInfo = undefined;
            const n = hw_info.fillMemRegions(&regions);
            break :blk hw_format.formatIomem(regions[0..n], dest);
        },
    };
}

fn fsRead(file: filesystem.OpenFile, offset: u64, buf: []u8) filesystem.Error!usize {
    const node = try nodeFromOpen(file);
    if (node == .root) return filesystem.Error.IsDirectory;
    var scratch: [4096]u8 = undefined;
    const len = render(node, &scratch);
    return seq.readAt(scratch[0..len], offset, buf);
}

fn fsWriteAt(_: *filesystem.OpenFile, _: u64, _: []const u8) filesystem.Error!usize {
    return filesystem.Error.ReadOnly;
}

fn fsStat(path: []const u8, out: *filesystem.Stat) filesystem.Error!void {
    const node = try resolve(path);
    out.* = .{};
    out.st_ino = @intFromEnum(node) + 1;
    out.st_nlink = 1;
    if (node == .root) {
        out.st_mode = filesystem.S_IFDIR | 0o555;
        out.st_size = 0;
    } else {
        out.st_mode = filesystem.S_IFREG | 0o444;
        var scratch: [4096]u8 = undefined;
        out.st_size = @intCast(render(node, &scratch));
    }
}

fn fsGetdents64(file: filesystem.OpenFile, dir_skip: *usize, buf: []u8) filesystem.Error!usize {
    const node = try nodeFromOpen(file);
    if (node != .root) return filesystem.Error.NotFile;

    if (dir_skip.* >= root_entries.len) return 0;
    var written: usize = 0;
    var index = dir_skip.*;
    while (index < root_entries.len) : (index += 1) {
        const e = root_entries[index];
        const reclen = abi_fs.dirent64Reclen(e.name.len);
        if (written + reclen > buf.len) {
            if (written == 0) return filesystem.Error.BufferTooSmall;
            dir_skip.* = index;
            return written;
        }
        abi_fs.writeDirent64(
            buf[written .. written + reclen],
            @intFromEnum(e.node) + 1,
            @intCast(index + 1),
            abi_fs.DT_REG,
            e.name,
        );
        written += reclen;
    }
    dir_skip.* = root_entries.len;
    return written;
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

pub fn resetForTest() void {
    mounted = false;
}
