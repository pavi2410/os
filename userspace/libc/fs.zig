const abi_fs = @import("abi_fs");
const syscall = @import("syscall.zig");

pub const O_RDONLY = abi_fs.O_RDONLY;
pub const O_WRONLY = abi_fs.O_WRONLY;
pub const O_RDWR = abi_fs.O_RDWR;
pub const O_ACCMODE = abi_fs.O_ACCMODE;
pub const O_CREAT = abi_fs.O_CREAT;
pub const O_TRUNC = abi_fs.O_TRUNC;
pub const O_APPEND = abi_fs.O_APPEND;

pub const SEEK_SET = abi_fs.SEEK_SET;
pub const SEEK_CUR = abi_fs.SEEK_CUR;
pub const SEEK_END = abi_fs.SEEK_END;

pub const S_IFREG = abi_fs.S_IFREG;
pub const S_IFDIR = abi_fs.S_IFDIR;

pub const Stat = abi_fs.Stat;
pub const Dirent64 = abi_fs.Dirent64;
pub const dirent64_name_offset = abi_fs.dirent64_name_offset;

pub fn open(path: [*:0]const u8, flags: u32, mode: u32) isize {
    return syscall.open(path, flags, mode);
}

pub fn close(fd: u32) isize {
    return syscall.close(fd);
}

pub fn read(fd: u32, buf: [*]u8, count: usize) isize {
    return syscall.read(fd, buf, count);
}

pub fn write(fd: u32, buf: [*]const u8, count: usize) isize {
    return syscall.write(fd, buf, count);
}

pub fn stat(path: [*:0]const u8, out: *Stat) isize {
    return syscall.stat(path, out);
}

pub fn getdents64(fd: u32, buf: [*]u8, count: usize) isize {
    return syscall.getdents64(fd, buf, count);
}
