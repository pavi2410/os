const fat32 = @import("fat32.zig");
const devfs = @import("devfs.zig");
const filesystem = @import("filesystem.zig");
const file_cache = @import("file_cache.zig");
const hal = @import("../hal.zig");
const std = @import("std");

pub const VfsError = filesystem.Error;

pub const Whence = filesystem.Whence;
pub const OpenFlags = filesystem.OpenFlags;
pub const Stat = filesystem.Stat;

pub const max_handles = 16;
/// Index into a Runtime-owned VFS open-file table.
pub const HandleId = u32;
const active_fs = fat32.ops;

const HandleKind = enum {
    fat,
    dev_root,
};

pub const Handle = struct {
    in_use: bool = false,
    refs: u16 = 0,
    kind: HandleKind = .fat,
    open: filesystem.OpenFile = .{},
    offset: u64 = 0,
    writable: bool = false,
    is_directory: bool = false,
    is_fs_root: bool = false,
    dir_skip: usize = 0,
    root_mount_emitted: bool = false,
};

/// Owns VFS open-file slots independently of mount policy. A later `Vfs`
/// context will compose this with filesystem and device backends.
pub const HandleTable = struct {
    slots: [max_handles]Handle = undefined,

    pub fn init(self: *HandleTable) void { self.slots = @splat(.{}); }
    pub fn alloc(self: *HandleTable) ?HandleId {
        for (&self.slots, 0..) |*slot, i| if (!slot.in_use) return @intCast(i);
        return null;
    }
    pub fn get(self: *HandleTable, handle: HandleId) VfsError!*Handle {
        if (handle >= max_handles or !self.slots[handle].in_use) return VfsError.BadHandle;
        return &self.slots[handle];
    }
    pub fn close(self: *HandleTable, handle: HandleId) void {
        const slot = self.get(handle) catch return;
        if (slot.refs == 0) return;
        slot.refs -= 1;
        if (slot.refs == 0) slot.* = .{};
    }
};

/// Runtime-owned filesystem service. Filesystem policy remains FAT32 + devfs
/// for now; callers retain the facade below during migration.
pub const Vfs = struct {
    handles: HandleTable = .{},

    pub fn init(self: *Vfs) VfsError!void {
        self.handles.init();
        try active_fs.mount();
        file_cache.bindOps(&active_fs);
    }

    pub fn isReady(_: *const Vfs) bool {
        return active_fs.is_ready();
    }

    pub fn open(self: *Vfs, path: []const u8, flags: OpenFlags) VfsError!HandleId {
    if (devfs.lookup(path)) |node| {
        return switch (node) {
            .root => self.openDevRoot(flags),
            .device => VfsError.NotFile,
        };
    }

    const opened = try active_fs.open(path, flags);

    if (!flags.read and !flags.write) return VfsError.InvalidWhence;
    if (flags.truncate and !flags.write) return VfsError.ReadOnly;

    const is_directory = opened.isDirectory();
    const slot = self.handles.alloc() orelse return VfsError.TooManyOpenFiles;
    self.handles.slots[slot] = .{
        .in_use = true,
        .refs = 1,
        .kind = .fat,
        .open = opened,
        .offset = if (flags.append and !is_directory) opened.size else 0,
        .writable = flags.write and !is_directory,
        .is_directory = is_directory,
        .is_fs_root = is_directory and path.len == 1 and path[0] == '/',
        .dir_skip = 0,
    };
    return slot;
    }

    pub fn close(self: *Vfs, handle: HandleId) void { self.handles.close(handle); }

    pub fn retain(self: *Vfs, handle: HandleId) VfsError!void {
    const h = try self.getHandle(handle);
    if (h.refs == std.math.maxInt(u16)) return VfsError.TooManyOpenFiles;
    h.refs += 1;
    }

    pub fn read(self: *Vfs, handle: HandleId, buf: []u8) VfsError!usize {
    const h = try self.getHandle(handle);
    if (h.is_directory) return VfsError.NotFile;
    if (h.kind == .dev_root) return VfsError.NotFile;
    const n = try file_cache.read(&active_fs, h.open, h.offset, buf);
    h.offset += n;
    return n;
    }

    pub fn write(self: *Vfs, handle: HandleId, buf: []const u8) VfsError!usize {
    const h = try self.getHandle(handle);
    if (h.is_directory) return VfsError.IsDirectory;
    if (h.kind == .dev_root) return VfsError.IsDirectory;
    if (!h.writable) return VfsError.ReadOnly;
    const n = try file_cache.write(&active_fs, &h.open, h.offset, buf);
    h.offset += n;
    return n;
    }

    pub fn fsync(self: *Vfs, handle: HandleId) VfsError!void {
        const h = try self.getHandle(handle);
        if (h.is_directory or h.kind == .dev_root) return;
        try file_cache.fsync(&active_fs, &h.open);
    }

    pub fn lseek(self: *Vfs, handle: HandleId, offset: i64, whence: Whence) VfsError!u64 {
    const h = try self.getHandle(handle);
    const size: u64 = if (h.kind == .dev_root) 0 else h.open.size;
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

    pub fn stat(_: *Vfs, path: []const u8, out: *Stat) VfsError!void {
    if (devfs.lookup(path)) |node| {
        devfs.stat(node, out);
        return;
    }
    try active_fs.stat(path, out);
    }

    pub fn getdents64(self: *Vfs, handle: HandleId, buf: []u8) VfsError!usize {
    const h = try self.getHandle(handle);
    if (!h.is_directory) return VfsError.NotFile;
    if (h.kind == .dev_root) return devfs.getdents64(&h.dir_skip, buf);

    const n = try active_fs.getdents64(h.open, &h.dir_skip, buf);
    if (n > 0) return n;

    if (!h.is_fs_root or h.root_mount_emitted) return 0;
    const extra = devfs.appendRootMountDirent(buf) orelse return 0;
    h.root_mount_emitted = true;
    return extra;
    }

    pub fn unlink(self: *Vfs, path: []const u8) VfsError!void {
    if (devfs.isDevPath(path)) return VfsError.ReadOnly;
    if (try active_fs.unlink(path)) |id| self.invalidateHandlesAt(id);
    }

    pub fn mkdir(_: *Vfs, path: []const u8) VfsError!void {
    if (devfs.isDevPath(path)) return VfsError.ReadOnly;
    try active_fs.mkdir(path);
    }

    pub fn rmdir(self: *Vfs, path: []const u8) VfsError!void {
    if (devfs.isDevPath(path)) return VfsError.ReadOnly;
    if (try active_fs.rmdir(path)) |id| self.invalidateHandlesAt(id);
    }

    fn invalidateHandlesAt(self: *Vfs, id: filesystem.FileId) void {
    var i: u32 = 0;
    while (i < max_handles) : (i += 1) {
        if (!self.handles.slots[i].in_use) continue;
        const h = &self.handles.slots[i];
        if (h.open.id.eql(id)) {
            self.handles.slots[i] = .{};
        }
    }
    }

    pub fn logStatus(self: *const Vfs) void {
    hal.console.println("\n--- VFS ---", .{});
    if (!self.isReady()) {
        hal.console.println("FAT32 not mounted", .{});
        return;
    }
    hal.console.println("FAT32 mounted (read/write)", .{});
    hal.console.println("devfs: /dev/null, /dev/zero, /dev/ttyS0", .{});
    }

    fn openDevRoot(self: *Vfs, flags: OpenFlags) VfsError!HandleId {
    if (!flags.read) return VfsError.InvalidWhence;
    if (flags.write or flags.create or flags.truncate) return VfsError.ReadOnly;

    const slot = self.handles.alloc() orelse return VfsError.TooManyOpenFiles;
    self.handles.slots[slot] = .{
        .in_use = true,
        .refs = 1,
        .kind = .dev_root,
        .is_directory = true,
    };
    return slot;
    }

    fn getHandle(self: *Vfs, handle: HandleId) VfsError!*Handle { return self.handles.get(handle); }
};
