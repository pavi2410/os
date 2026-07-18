const view = @import("common/view");

pub const O_RDONLY: u32 = 0;
pub const O_WRONLY: u32 = 0o1;
pub const O_RDWR: u32 = 0o2;
pub const O_ACCMODE: u32 = 0o3;
pub const O_CREAT: u32 = 0o100;
pub const O_TRUNC: u32 = 0o1000;
pub const O_APPEND: u32 = 0o2000;

/// Access mode bits of a Linux `open` flags word (`flags & O_ACCMODE`).
pub const AccMode = enum(u2) {
    rdonly = 0,
    wronly = 1,
    rdwr = 2,

    pub fn fromFlags(flags: u32) ?AccMode {
        return switch (flags & O_ACCMODE) {
            @intFromEnum(AccMode.rdonly) => .rdonly,
            @intFromEnum(AccMode.wronly) => .wronly,
            @intFromEnum(AccMode.rdwr) => .rdwr,
            else => null,
        };
    }
};

pub const Seek = enum(u32) {
    set = 0,
    cur = 1,
    end = 2,

    pub fn fromInt(n: u32) ?Seek {
        return switch (n) {
            @intFromEnum(Seek.set) => .set,
            @intFromEnum(Seek.cur) => .cur,
            @intFromEnum(Seek.end) => .end,
            else => null,
        };
    }
};

pub const SEEK_SET: u32 = @intFromEnum(Seek.set);
pub const SEEK_CUR: u32 = @intFromEnum(Seek.cur);
pub const SEEK_END: u32 = @intFromEnum(Seek.end);

/// File type bits in `st_mode` (`mode & S_IFMT`).
pub const ModeType = enum(u32) {
    chr = 0o020000,
    dir = 0o040000,
    reg = 0o100000,
    lnk = 0o120000,

    pub const mask: u32 = 0o170000;

    pub fn fromMode(mode: u32) ?ModeType {
        return switch (mode & mask) {
            @intFromEnum(ModeType.chr) => .chr,
            @intFromEnum(ModeType.dir) => .dir,
            @intFromEnum(ModeType.reg) => .reg,
            @intFromEnum(ModeType.lnk) => .lnk,
            else => null,
        };
    }
};

pub const S_IFMT: u32 = ModeType.mask;
pub const S_IFREG: u32 = @intFromEnum(ModeType.reg);
pub const S_IFDIR: u32 = @intFromEnum(ModeType.dir);
pub const S_IFCHR: u32 = @intFromEnum(ModeType.chr);
pub const S_IFLNK: u32 = @intFromEnum(ModeType.lnk);

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

pub const Dirent64 = extern struct {
    d_ino: u64,
    d_off: i64,
    d_reclen: u16,
    d_type: u8,
};

pub const dirent64_name_offset: usize = 19;

pub const DirentType = enum(u8) {
    chr = 2,
    dir = 4,
    reg = 8,
    lnk = 10,

    pub fn fromInt(n: u8) ?DirentType {
        return switch (n) {
            @intFromEnum(DirentType.chr) => .chr,
            @intFromEnum(DirentType.dir) => .dir,
            @intFromEnum(DirentType.reg) => .reg,
            @intFromEnum(DirentType.lnk) => .lnk,
            else => null,
        };
    }
};

pub const DT_CHR: u8 = @intFromEnum(DirentType.chr);
pub const DT_DIR: u8 = @intFromEnum(DirentType.dir);
pub const DT_REG: u8 = @intFromEnum(DirentType.reg);
pub const DT_LNK: u8 = @intFromEnum(DirentType.lnk);

pub fn dirent64Reclen(name_len: usize) usize {
    const raw = dirent64_name_offset + name_len + 1;
    return (raw + 7) & ~@as(usize, 7);
}

pub const Dirent64Entry = struct {
    header: *const Dirent64,
    name: []const u8,
};

pub const Dirent64Iterator = struct {
    data: []const u8,
    off: usize = 0,

    pub fn next(self: *Dirent64Iterator) ?Dirent64Entry {
        if (self.off + dirent64_name_offset > self.data.len) return null;
        const hdr = view.get(Dirent64, self.data, self.off) orelse return null;
        const reclen = hdr.d_reclen;
        if (reclen < dirent64_name_offset or self.off + reclen > self.data.len) return null;

        const name_start = self.off + dirent64_name_offset;
        var name_len: usize = 0;
        while (name_len < reclen - dirent64_name_offset and self.data[name_start + name_len] != 0) {
            name_len += 1;
        }
        const entry = Dirent64Entry{
            .header = hdr,
            .name = self.data[name_start .. name_start + name_len],
        };
        self.off += reclen;
        return entry;
    }
};

pub fn writeDirent64(out: []u8, ino: u64, off: i64, d_type: DirentType, name: []const u8) void {
    const reclen = dirent64Reclen(name.len);
    @memset(out[0..reclen], 0);
    const hdr = view.mut(Dirent64, out, 0).?;
    hdr.d_ino = ino;
    hdr.d_off = off;
    hdr.d_reclen = @intCast(reclen);
    hdr.d_type = @intFromEnum(d_type);
    @memcpy(out[dirent64_name_offset .. dirent64_name_offset + name.len], name);
    out[dirent64_name_offset + name.len] = 0;
}

comptime {
    if (@intFromEnum(Seek.set) != 0) @compileError("Seek.set must be 0");
    if (@intFromEnum(Seek.cur) != 1) @compileError("Seek.cur must be 1");
    if (@intFromEnum(Seek.end) != 2) @compileError("Seek.end must be 2");
    if (@intFromEnum(DirentType.dir) != 4) @compileError("DirentType.dir must be 4");
    if (@intFromEnum(ModeType.dir) != 0o040000) @compileError("ModeType.dir ABI drift");
}
