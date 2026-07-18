const abi_fs = @import("abi_fs");

pub const FatError = error{
    NotReady,
    InvalidBpb,
    NotFound,
    NotFile,
    IsDirectory,
    IoError,
    NameTooLong,
    PathTooLong,
    BufferTooSmall,
    Exists,
    NoSpace,
    NotEmpty,
};

pub const Error = FatError || error{
    TooManyOpenFiles,
    BadHandle,
    InvalidWhence,
    ReadOnly,
    Busy,
    NotSupported,
    CrossDevice,
};

/// Maps a FAT32-layer error into the shared filesystem error set.
pub fn liftFat(err: FatError) Error {
    return err;
}

/// Maps a filesystem error to the negative errno values returned by syscalls.
pub fn errnoCode(err: Error) i64 {
    return switch (err) {
        error.NotFound => -2,
        error.IsDirectory => -21,
        error.BadHandle => -9,
        error.TooManyOpenFiles => -24,
        error.InvalidWhence => -22,
        error.NotReady, error.IoError, error.InvalidBpb => -5,
        error.NotFile => -22,
        error.NameTooLong, error.PathTooLong, error.BufferTooSmall => -22,
        error.Exists => -17,
        error.NoSpace => -28,
        error.NotEmpty => -39,
        error.ReadOnly => -13,
        error.Busy => -16,
        error.NotSupported => -95,
        error.CrossDevice => -18,
    };
}

pub const Whence = abi_fs.Seek;

pub const OpenFlags = packed struct(u8) {
    read: bool = true,
    write: bool = false,
    create: bool = false,
    truncate: bool = false,
    append: bool = false,
    _: u3 = 0,
};

comptime {
    if (@sizeOf(OpenFlags) != 1) @compileError("OpenFlags must fit in one byte");
}

pub const Stat = abi_fs.Stat;
pub const S_IFREG = abi_fs.S_IFREG;
pub const S_IFDIR = abi_fs.S_IFDIR;
pub const S_IFLNK = abi_fs.S_IFLNK;

pub const FileId = struct {
    a: u64 = 0,
    b: u64 = 0,

    pub fn eql(self: FileId, other: FileId) bool {
        return self.a == other.a and self.b == other.b;
    }
};

pub const OpenFile = struct {
    id: FileId = .{},
    start_cluster: u32 = 0,
    size: u32 = 0,
    attr: u8 = 0,
    loc_cluster: u32 = 0,
    loc_offset: u32 = 0,

    pub fn isDirectory(self: OpenFile) bool {
        return self.attr & 0x10 != 0;
    }
};

pub const Ops = struct {
    name: []const u8,
    mount: *const fn () Error!void,
    is_ready: *const fn () bool,
    open: *const fn (path: []const u8, flags: OpenFlags) Error!OpenFile,
    read: *const fn (file: OpenFile, offset: u64, buf: []u8) Error!usize,
    write_at: *const fn (file: *OpenFile, offset: u64, buf: []const u8) Error!usize,
    stat: *const fn (path: []const u8, out: *Stat) Error!void,
    getdents64: *const fn (file: OpenFile, dir_skip: *usize, buf: []u8) Error!usize,
    unlink: *const fn (path: []const u8) Error!?FileId,
    mkdir: *const fn (path: []const u8) Error!void,
    rmdir: *const fn (path: []const u8) Error!?FileId,
    rename: ?*const fn (old_path: []const u8, new_path: []const u8) Error!void = null,
    symlink: ?*const fn (target: []const u8, linkpath: []const u8) Error!void = null,
    readlink: ?*const fn (path: []const u8, buf: []u8) Error!usize = null,
    /// When false, VFS skips the page cache (procfs/sysfs generate-on-read).
    use_page_cache: bool = true,
};
