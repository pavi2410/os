//! Read-only `/sys` pseudo filesystem (seq-style generate-on-read).
//!
//! Layout:
//! - `/sys/bus/pci/devices/<BB:DD.F>/{vendor,device,class}`
//! - `/sys/block/<name>/{size,sector_size}`

const abi_fs = @import("abi_fs");
const filesystem = @import("filesystem.zig");
const seq = @import("seq.zig");
const hw_format = @import("../hw/format.zig");
const block = @import("../drivers/block.zig");
const pci = @import("../drivers/pci.zig");
const std = @import("std");

const sys_magic: u64 = 0x73797366; // "sysf"
const attr_dir: u8 = 0x10;
const attr_file: u8 = 0x20;

const Kind = enum(u8) {
    root = 0,
    bus = 1,
    bus_pci = 2,
    bus_pci_devices = 3,
    pci_dev = 4,
    pci_vendor = 5,
    pci_device = 6,
    pci_class = 7,
    block_root = 8,
    block_dev = 9,
    block_size = 10,
    block_sector_size = 11,
};

const Resolved = struct {
    kind: Kind,
    /// Index into `pci.devices()` when kind is pci_*.
    pci_index: u16 = 0,
};

var mounted: bool = false;

pub const ops: filesystem.Ops = .{
    .name = "sysfs",
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

fn toOpenFile(r: Resolved) filesystem.OpenFile {
    const is_dir = switch (r.kind) {
        .root, .bus, .bus_pci, .bus_pci_devices, .pci_dev, .block_root, .block_dev => true,
        else => false,
    };
    return .{
        .id = .{ .a = @intFromEnum(r.kind), .b = sys_magic },
        .start_cluster = r.pci_index,
        .size = 0,
        .attr = if (is_dir) attr_dir else attr_file,
        .loc_cluster = r.pci_index,
        .loc_offset = @intFromEnum(r.kind),
    };
}

fn fromOpenFile(file: filesystem.OpenFile) filesystem.Error!Resolved {
    if (file.id.b != sys_magic) return filesystem.Error.BadHandle;
    if (file.id.a > @intFromEnum(Kind.block_sector_size)) return filesystem.Error.BadHandle;
    return .{
        .kind = @enumFromInt(file.id.a),
        .pci_index = @intCast(file.loc_cluster),
    };
}

fn nextComponent(path: []const u8, start: usize) struct { name: []const u8, next: usize } {
    var s = start;
    while (s < path.len and path[s] == '/') : (s += 1) {}
    if (s >= path.len) return .{ .name = "", .next = path.len };
    var e = s;
    while (e < path.len and path[e] != '/') : (e += 1) {}
    return .{ .name = path[s..e], .next = e };
}

fn findPciIndex(bus: u8, device: u8, function: u8) ?u16 {
    const list = pci.devices();
    var i: usize = 0;
    while (i < list.len) : (i += 1) {
        const d = list[i];
        if (d.bus == bus and d.device == device and d.function == function) return @intCast(i);
    }
    return null;
}

fn blockName() ?[]const u8 {
    const dev = block.default() orelse return null;
    if (!dev.isReady()) return null;
    return dev.name;
}

fn resolve(path: []const u8) filesystem.Error!Resolved {
    if (!mounted) return filesystem.Error.NotReady;
    if (path.len == 0 or path[0] != '/') return filesystem.Error.NotFound;
    if (path.len == 1) return .{ .kind = .root };

    var c = nextComponent(path, 1);
    if (c.name.len == 0) return .{ .kind = .root };

    if (std.mem.eql(u8, c.name, "bus")) {
        c = nextComponent(path, c.next);
        if (c.name.len == 0) return .{ .kind = .bus };
        if (!std.mem.eql(u8, c.name, "pci")) return filesystem.Error.NotFound;
        c = nextComponent(path, c.next);
        if (c.name.len == 0) return .{ .kind = .bus_pci };
        if (!std.mem.eql(u8, c.name, "devices")) return filesystem.Error.NotFound;
        c = nextComponent(path, c.next);
        if (c.name.len == 0) return .{ .kind = .bus_pci_devices };

        var bus: u8 = 0;
        var device: u8 = 0;
        var function: u8 = 0;
        if (!hw_format.parsePciAddr(c.name, &bus, &device, &function)) return filesystem.Error.NotFound;
        const idx = findPciIndex(bus, device, function) orelse return filesystem.Error.NotFound;
        const after_dev = c.next;
        c = nextComponent(path, after_dev);
        if (c.name.len == 0) return .{ .kind = .pci_dev, .pci_index = idx };
        const attr: Kind = if (std.mem.eql(u8, c.name, "vendor"))
            .pci_vendor
        else if (std.mem.eql(u8, c.name, "device"))
            .pci_device
        else if (std.mem.eql(u8, c.name, "class"))
            .pci_class
        else
            return filesystem.Error.NotFound;
        c = nextComponent(path, c.next);
        if (c.name.len != 0) return filesystem.Error.NotFound;
        return .{ .kind = attr, .pci_index = idx };
    }

    if (std.mem.eql(u8, c.name, "block")) {
        c = nextComponent(path, c.next);
        if (c.name.len == 0) return .{ .kind = .block_root };
        const bname = blockName() orelse return filesystem.Error.NotFound;
        if (!std.mem.eql(u8, c.name, bname)) return filesystem.Error.NotFound;
        c = nextComponent(path, c.next);
        if (c.name.len == 0) return .{ .kind = .block_dev };
        const attr: Kind = if (std.mem.eql(u8, c.name, "size"))
            .block_size
        else if (std.mem.eql(u8, c.name, "sector_size"))
            .block_sector_size
        else
            return filesystem.Error.NotFound;
        c = nextComponent(path, c.next);
        if (c.name.len != 0) return filesystem.Error.NotFound;
        return .{ .kind = attr };
    }

    return filesystem.Error.NotFound;
}

fn fsOpen(path: []const u8, flags: filesystem.OpenFlags) filesystem.Error!filesystem.OpenFile {
    if (flags.write or flags.create or flags.truncate or flags.append) return filesystem.Error.ReadOnly;
    if (!flags.read) return filesystem.Error.InvalidWhence;
    return toOpenFile(try resolve(path));
}

fn render(r: Resolved, dest: []u8) usize {
    return switch (r.kind) {
        .pci_vendor => blk: {
            const list = pci.devices();
            if (r.pci_index >= list.len) break :blk 0;
            break :blk hw_format.formatHexAttr(list[r.pci_index].vendor_id, 4, dest);
        },
        .pci_device => blk: {
            const list = pci.devices();
            if (r.pci_index >= list.len) break :blk 0;
            break :blk hw_format.formatHexAttr(list[r.pci_index].device_id, 4, dest);
        },
        .pci_class => blk: {
            const list = pci.devices();
            if (r.pci_index >= list.len) break :blk 0;
            const d = list[r.pci_index];
            const packed_class: u32 = (@as(u32, d.class_code) << 16) |
                (@as(u32, d.subclass) << 8) |
                @as(u32, d.prog_if);
            break :blk hw_format.formatHexAttr(packed_class, 6, dest);
        },
        .block_size => blk: {
            const dev = block.default() orelse break :blk 0;
            if (!dev.isReady()) break :blk 0;
            break :blk hw_format.formatU64Attr(dev.capacity(), dest);
        },
        .block_sector_size => blk: {
            const dev = block.default() orelse break :blk 0;
            if (!dev.isReady()) break :blk 0;
            break :blk hw_format.formatU64Attr(dev.sectorSize(), dest);
        },
        else => 0,
    };
}

fn isDir(kind: Kind) bool {
    return switch (kind) {
        .root, .bus, .bus_pci, .bus_pci_devices, .pci_dev, .block_root, .block_dev => true,
        else => false,
    };
}

fn fsRead(file: filesystem.OpenFile, offset: u64, buf: []u8) filesystem.Error!usize {
    const r = try fromOpenFile(file);
    if (isDir(r.kind)) return filesystem.Error.IsDirectory;
    var scratch: [64]u8 = undefined;
    const len = render(r, &scratch);
    return seq.readAt(scratch[0..len], offset, buf);
}

fn fsWriteAt(_: *filesystem.OpenFile, _: u64, _: []const u8) filesystem.Error!usize {
    return filesystem.Error.ReadOnly;
}

fn fsStat(path: []const u8, out: *filesystem.Stat) filesystem.Error!void {
    const r = try resolve(path);
    out.* = .{};
    out.st_ino = ((@as(u64, @intFromEnum(r.kind)) << 16) | r.pci_index) + 1;
    out.st_nlink = 1;
    if (isDir(r.kind)) {
        out.st_mode = filesystem.ModeType.dir.withPerms(0o555);
        out.st_size = 0;
    } else {
        out.st_mode = filesystem.ModeType.reg.withPerms(0o444);
        var scratch: [64]u8 = undefined;
        out.st_size = @intCast(render(r, &scratch));
    }
}

fn emitDent(buf: []u8, written: *usize, dir_skip: *usize, index: usize, ino: u64, dtype: abi_fs.DirentType, name: []const u8) filesystem.Error!?usize {
    const reclen = abi_fs.dirent64Reclen(name.len);
    if (written.* + reclen > buf.len) {
        if (written.* == 0) return filesystem.Error.BufferTooSmall;
        dir_skip.* = index;
        return written.*;
    }
    abi_fs.writeDirent64(buf[written.* .. written.* + reclen], ino, @intCast(index + 1), dtype, name);
    written.* += reclen;
    return null;
}

fn fsGetdents64(file: filesystem.OpenFile, dir_skip: *usize, buf: []u8) filesystem.Error!usize {
    const r = try fromOpenFile(file);
    if (!isDir(r.kind)) return filesystem.Error.NotFile;

    var written: usize = 0;
    var index = dir_skip.*;

    switch (r.kind) {
        .root => {
            const names = [_][]const u8{ "bus", "block" };
            while (index < names.len) : (index += 1) {
                if (try emitDent(buf, &written, dir_skip, index, 10 + index, .dir, names[index])) |n| return n;
            }
        },
        .bus => {
            if (index == 0) {
                if (try emitDent(buf, &written, dir_skip, 0, 20, .dir, "pci")) |n| return n;
                index = 1;
            }
        },
        .bus_pci => {
            if (index == 0) {
                if (try emitDent(buf, &written, dir_skip, 0, 30, .dir, "devices")) |n| return n;
                index = 1;
            }
        },
        .bus_pci_devices => {
            const list = pci.devices();
            while (index < list.len) : (index += 1) {
                var name_buf: [8]u8 = undefined;
                const d = list[index];
                const nlen = hw_format.formatPciAddr(d.bus, d.device, d.function, &name_buf);
                if (try emitDent(buf, &written, dir_skip, index, 100 + index, .dir, name_buf[0..nlen])) |n| return n;
            }
        },
        .pci_dev => {
            const names = [_][]const u8{ "vendor", "device", "class" };
            while (index < names.len) : (index += 1) {
                if (try emitDent(buf, &written, dir_skip, index, 200 + index, .reg, names[index])) |n| return n;
            }
        },
        .block_root => {
            if (index == 0) {
                if (blockName()) |name| {
                    if (try emitDent(buf, &written, dir_skip, 0, 300, .dir, name)) |n| return n;
                }
                index = 1;
            }
        },
        .block_dev => {
            const names = [_][]const u8{ "size", "sector_size" };
            while (index < names.len) : (index += 1) {
                if (try emitDent(buf, &written, dir_skip, index, 400 + index, .reg, names[index])) |n| return n;
            }
        },
        else => return filesystem.Error.NotFile,
    }

    dir_skip.* = index;
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
