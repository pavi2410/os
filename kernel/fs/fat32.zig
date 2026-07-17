const std = @import("std");
const bytes = @import("common/bytes");
const block = @import("../drivers/block.zig");
const core = @import("fat32/core.zig");
const dir = @import("fat32/dir.zig");
const file = @import("fat32/file.zig");
const filesystem = @import("filesystem.zig");

pub const FatError = core.FatError;
pub const Entry = core.Entry;
pub const DirLoc = core.DirLoc;
pub const OpenResult = core.OpenResult;

pub const lookup = dir.lookup;
pub const read = file.read;
pub const openFile = file.openFile;
pub const createFile = file.createFile;
pub const writeAt = file.writeAt;
pub const unlinkFile = file.unlinkFile;
pub const createDirectory = dir.createDirectory;
pub const removeDirectory = dir.removeDirectory;
pub const openDirectory = dir.openDirectory;
pub const getDents64 = dir.getDents64;

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
    .rename = fsRename,
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

fn fsMount() filesystem.Error!void {
    mount() catch |err| return filesystem.liftFat(err);
}

fn fsOpen(path_str: []const u8, flags: filesystem.OpenFlags) filesystem.Error!filesystem.OpenFile {
    const opened: OpenResult = blk: {
        if (dir.lookup(path_str)) |entry| {
            if (entry.attr & 0x10 != 0) {
                if (flags.write or flags.create or flags.truncate) return filesystem.Error.IsDirectory;
                if (!flags.read) return filesystem.Error.IsDirectory;
                break :blk dir.openDirectory(path_str) catch |err| return filesystem.liftFat(err);
            }
            break :blk file.openFile(path_str, flags.truncate) catch |err| return filesystem.liftFat(err);
        } else |_| {
            if (!flags.create) return filesystem.Error.NotFound;
            break :blk file.createFile(path_str) catch |err| return filesystem.liftFat(err);
        }
    };
    return toFsFile(opened);
}

fn fsRead(opened_file: filesystem.OpenFile, offset: u64, buf: []u8) filesystem.Error!usize {
    return read(fromFsFile(opened_file).entry, offset, buf) catch |err| return filesystem.liftFat(err);
}

fn fsWriteAt(opened_file: *filesystem.OpenFile, offset: u64, buf: []const u8) filesystem.Error!usize {
    var opened = fromFsFile(opened_file.*);
    const n = writeAt(&opened, offset, buf) catch |err| return filesystem.liftFat(err);
    opened_file.* = toFsFile(opened);
    return n;
}

fn fsStat(path_str: []const u8, out: *filesystem.Stat) filesystem.Error!void {
    const entry = lookup(path_str) catch |err| return filesystem.liftFat(err);
    out.* = .{};
    out.st_mode = if (entry.attr & 0x10 != 0) filesystem.S_IFDIR | 0o755 else filesystem.S_IFREG | 0o644;
    out.st_size = @intCast(entry.size);
}

fn fsGetDents64(opened_file: filesystem.OpenFile, dir_skip: *usize, buf: []u8) filesystem.Error!usize {
    return getDents64(opened_file.start_cluster, dir_skip, buf) catch |err| return filesystem.liftFat(err);
}

fn fsUnlink(path_str: []const u8) filesystem.Error!?filesystem.FileId {
    const loc = unlinkFile(path_str) catch |err| return filesystem.liftFat(err);
    return fileId(loc);
}

fn fsMkdir(path_str: []const u8) filesystem.Error!void {
    createDirectory(path_str) catch |err| return filesystem.liftFat(err);
}

fn fsRmdir(path_str: []const u8) filesystem.Error!?filesystem.FileId {
    const loc = removeDirectory(path_str) catch |err| return filesystem.liftFat(err);
    return fileId(loc);
}

fn fsRename(old_path: []const u8, new_path: []const u8) filesystem.Error!void {
    dir.renamePath(old_path, new_path) catch |err| return filesystem.liftFat(err);
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

fn fromFsFile(opened_file: filesystem.OpenFile) OpenResult {
    return .{
        .entry = .{
            .start_cluster = opened_file.start_cluster,
            .size = opened_file.size,
            .attr = opened_file.attr,
        },
        .loc = .{
            .cluster = opened_file.loc_cluster,
            .offset = opened_file.loc_offset,
        },
    };
}

fn fileId(loc: DirLoc) filesystem.FileId {
    return .{ .a = loc.cluster, .b = loc.offset };
}
