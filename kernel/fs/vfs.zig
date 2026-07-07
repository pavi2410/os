const fat32 = @import("fat32.zig");
const filesystem = @import("filesystem.zig");
const hal = @import("../hal.zig");

pub const VfsError = filesystem.Error || error{
    TooManyOpenFiles,
    BadHandle,
    InvalidWhence,
    ReadOnly,
};

pub const Whence = filesystem.Whence;
pub const OpenFlags = filesystem.OpenFlags;
pub const Stat = filesystem.Stat;

const max_handles = 16;
const active_fs = fat32.ops;

const Handle = struct {
    in_use: bool = false,
    open: filesystem.OpenFile = .{},
    offset: u64 = 0,
    writable: bool = false,
    is_directory: bool = false,
    dir_skip: usize = 0,
};

var handles: [max_handles]Handle = undefined;

pub fn init() VfsError!void {
    try active_fs.mount();
}

pub fn isReady() bool {
    return active_fs.is_ready();
}

pub fn open(path: []const u8, flags: OpenFlags) VfsError!u32 {
    const opened = try active_fs.open(path, flags);

    if (!flags.read and !flags.write) return VfsError.InvalidWhence;
    if (flags.truncate and !flags.write) return VfsError.ReadOnly;

    const is_directory = opened.isDirectory();
    const slot = allocHandle() orelse return VfsError.TooManyOpenFiles;
    handles[slot] = .{
        .in_use = true,
        .open = opened,
        .offset = if (flags.append and !is_directory) opened.size else 0,
        .writable = flags.write and !is_directory,
        .is_directory = is_directory,
        .dir_skip = 0,
    };
    return slot;
}

pub fn close(handle: u32) void {
    if (handle >= max_handles) return;
    handles[handle] = .{};
}

pub fn read(handle: u32, buf: []u8) VfsError!usize {
    const h = try getHandle(handle);
    if (h.is_directory) return VfsError.NotFile;
    const n = try active_fs.read(h.open, h.offset, buf);
    h.offset += n;
    return n;
}

pub fn write(handle: u32, buf: []const u8) VfsError!usize {
    const h = try getHandle(handle);
    if (h.is_directory) return VfsError.IsDirectory;
    if (!h.writable) return VfsError.ReadOnly;
    const n = try active_fs.write_at(&h.open, h.offset, buf);
    h.offset += n;
    return n;
}

pub fn lseek(handle: u32, offset: i64, whence: Whence) VfsError!u64 {
    const h = try getHandle(handle);
    const size: u64 = h.open.size;
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
    try active_fs.stat(path, out);
}

pub fn getdents64(handle: u32, buf: []u8) VfsError!usize {
    const h = try getHandle(handle);
    if (!h.is_directory) return VfsError.NotFile;
    return active_fs.getdents64(h.open, &h.dir_skip, buf);
}

pub fn unlink(path: []const u8) VfsError!void {
    if (try active_fs.unlink(path)) |id| invalidateHandlesAt(id);
}

pub fn mkdir(path: []const u8) VfsError!void {
    try active_fs.mkdir(path);
}

pub fn rmdir(path: []const u8) VfsError!void {
    if (try active_fs.rmdir(path)) |id| invalidateHandlesAt(id);
}

fn invalidateHandlesAt(id: filesystem.FileId) void {
    var i: u32 = 0;
    while (i < max_handles) : (i += 1) {
        if (!handles[i].in_use) continue;
        const h = &handles[i];
        if (h.open.id.eql(id)) {
            handles[i] = .{};
        }
    }
}

pub fn logStatus() void {
    hal.console.writeString("\r\n--- VFS ---\r\n");
    if (!isReady()) {
        hal.console.writeString("FAT32 not mounted\r\n");
        return;
    }
    hal.console.writeString("FAT32 mounted (read/write)\r\n");
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
