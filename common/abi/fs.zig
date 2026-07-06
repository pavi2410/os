const view = @import("common_view");

pub const O_RDONLY: u32 = 0;
pub const O_WRONLY: u32 = 0o1;
pub const O_RDWR: u32 = 0o2;
pub const O_ACCMODE: u32 = 0o3;
pub const O_CREAT: u32 = 0o100;
pub const O_TRUNC: u32 = 0o1000;
pub const O_APPEND: u32 = 0o2000;

pub const SEEK_SET: u32 = 0;
pub const SEEK_CUR: u32 = 1;
pub const SEEK_END: u32 = 2;

pub const S_IFREG: u32 = 0o100000;
pub const S_IFDIR: u32 = 0o040000;

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

pub const DT_DIR: u8 = 4;
pub const DT_REG: u8 = 8;

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

pub fn writeDirent64(out: []u8, ino: u64, off: i64, d_type: u8, name: []const u8) void {
    const reclen = dirent64Reclen(name.len);
    @memset(out[0..reclen], 0);
    const hdr = view.mut(Dirent64, out, 0).?;
    hdr.d_ino = ino;
    hdr.d_off = off;
    hdr.d_reclen = @intCast(reclen);
    hdr.d_type = d_type;
    @memcpy(out[dirent64_name_offset .. dirent64_name_offset + name.len], name);
    out[dirent64_name_offset + name.len] = 0;
}
