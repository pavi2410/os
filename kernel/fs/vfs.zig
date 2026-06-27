const fat32 = @import("fat32.zig");
const serial = @import("../arch/x86_64/serial.zig");

pub const VfsError = fat32.FatError || error{
    TooManyOpenFiles,
    BadHandle,
    InvalidWhence,
    ReadOnly,
};

pub const Whence = enum(u32) {
    set = 0,
    cur = 1,
    end = 2,
};

pub const OpenFlags = struct {
    read: bool = true,
    write: bool = false,
    create: bool = false,
    truncate: bool = false,
    append: bool = false,
};

pub const Stat = extern struct {
    st_dev: u64 = 0,
    st_ino: u64 = 0,
    st_nlink: u64 = 1,
    st_mode: u32 = 0,
    _pad0: u32 = 0,
    st_uid: u32 = 0,
    st_gid: u32 = 0,
    _pad1: u32 = 0,
    st_rdev: u64 = 0,
    st_size: i64 = 0,
    st_blksize: i64 = 4096,
    st_blocks: i64 = 0,
    st_atime: i64 = 0,
    st_mtime: i64 = 0,
    st_ctime: i64 = 0,
    _pad2: [24]u8 = .{0} ** 24,
};

const S_IFREG: u32 = 0o100000;
const S_IFDIR: u32 = 0o040000;

const max_handles = 16;

const Handle = struct {
    in_use: bool = false,
    open: fat32.OpenResult = .{
        .entry = .{ .start_cluster = 0, .size = 0, .attr = 0 },
        .loc = .{ .cluster = 0, .offset = 0 },
    },
    offset: u64 = 0,
    writable: bool = false,
};

var handles: [max_handles]Handle = undefined;

pub fn init() VfsError!void {
    try fat32.mount();
}

pub fn isReady() bool {
    return fat32.isMounted();
}

pub fn open(path: []const u8, flags: OpenFlags) VfsError!u32 {
    const opened: fat32.OpenResult = blk: {
        if (fat32.lookup(path)) |entry| {
            if (entry.attr & 0x10 != 0) return VfsError.IsDirectory;
            break :blk try fat32.openFile(path, flags.truncate);
        } else |_| {
            if (!flags.create) return VfsError.NotFound;
            break :blk try fat32.createFile(path);
        }
    };

    if (!flags.read and !flags.write) return VfsError.InvalidWhence;
    if (flags.truncate and !flags.write) return VfsError.ReadOnly;

    const slot = allocHandle() orelse return VfsError.TooManyOpenFiles;
    handles[slot] = .{
        .in_use = true,
        .open = opened,
        .offset = if (flags.append) opened.entry.size else 0,
        .writable = flags.write,
    };
    return slot;
}

pub fn close(handle: u32) void {
    if (handle >= max_handles) return;
    handles[handle] = .{};
}

pub fn read(handle: u32, buf: []u8) VfsError!usize {
    const h = try getHandle(handle);
    const n = try fat32.read(h.open.entry, h.offset, buf);
    h.offset += n;
    return n;
}

pub fn write(handle: u32, buf: []const u8) VfsError!usize {
    const h = try getHandle(handle);
    if (!h.writable) return VfsError.ReadOnly;
    const n = try fat32.writeAt(&h.open, h.offset, buf);
    h.offset += n;
    return n;
}

pub fn lseek(handle: u32, offset: i64, whence: Whence) VfsError!u64 {
    const h = try getHandle(handle);
    const size: u64 = h.open.entry.size;
    const new_off: u64 = switch (whence) {
        .set => {
            if (offset < 0) return VfsError.InvalidWhence;
            return @intCast(offset);
        },
        .cur => {
            if (offset < 0) {
                const sub: u64 = @intCast(-offset);
                if (sub > h.offset) return VfsError.InvalidWhence;
                return h.offset - sub;
            }
            return h.offset + @as(u64, @intCast(offset));
        },
        .end => {
            if (offset < 0) {
                const sub: u64 = @intCast(-offset);
                if (sub > size) return VfsError.InvalidWhence;
                return size - sub;
            }
            return size + @as(u64, @intCast(offset));
        },
    };
    h.offset = new_off;
    return new_off;
}

pub fn stat(path: []const u8, out: *Stat) VfsError!void {
    const entry = try fat32.lookup(path);
    out.* = .{};
    out.st_mode = if (entry.attr & 0x10 != 0) S_IFDIR | 0o755 else S_IFREG | 0o644;
    out.st_size = @intCast(entry.size);
}

pub fn listDir(path: []const u8, out: []u8) VfsError!usize {
    return fat32.listDir(path, out);
}

pub fn logStatus() void {
    serial.writeString("\r\n--- VFS ---\r\n");
    if (!isReady()) {
        serial.writeString("FAT32 not mounted\r\n");
        return;
    }
    serial.writeString("FAT32 mounted (read/write)\r\n");
}

pub fn selfTest() void {
    if (!isReady()) return;

    var buf: [64]u8 = undefined;
    const entry = fat32.lookup("/README.TXT") catch {
        serial.writeString("vfs: /README.TXT not found\r\n");
        return;
    };
    const n = fat32.read(entry, 0, &buf) catch {
        serial.writeString("vfs read test failed\r\n");
        return;
    };
    serial.printf("vfs: readme {d} bytes\r\n", .{n});
}

fn getHandle(handle: u32) VfsError!*Handle {
    if (handle >= max_handles or !handles[handle].in_use) return VfsError.BadHandle;
    return &handles[handle];
}

fn allocHandle() ?u32 {
    var i: u32 = 0;
    while (i < max_handles) : (i += 1) {
        if (!handles[i].in_use) return i;
    }
    return null;
}
