const abi_fs = @import("abi_fs");
const syscall = @import("syscall.zig");

/// Kernel descriptor number; syscall results remain signed errno values.
pub const Descriptor = u32;
pub const Result = i64;

pub const O_RDONLY = abi_fs.O_RDONLY;
pub const O_WRONLY = abi_fs.O_WRONLY;
pub const O_RDWR = abi_fs.O_RDWR;
pub const O_ACCMODE = abi_fs.O_ACCMODE;
pub const O_CREAT = abi_fs.O_CREAT;
pub const O_TRUNC = abi_fs.O_TRUNC;
pub const O_APPEND = abi_fs.O_APPEND;

pub const Seek = abi_fs.Seek;
pub const SEEK_SET = abi_fs.SEEK_SET;
pub const SEEK_CUR = abi_fs.SEEK_CUR;
pub const SEEK_END = abi_fs.SEEK_END;

pub const ModeType = abi_fs.ModeType;
pub const S_IFREG = abi_fs.S_IFREG;
pub const S_IFDIR = abi_fs.S_IFDIR;
pub const S_IFCHR = abi_fs.S_IFCHR;

pub const Stat = abi_fs.Stat;
pub const Dirent64 = abi_fs.Dirent64;
pub const dirent64_name_offset = abi_fs.dirent64_name_offset;
pub const DirentType = abi_fs.DirentType;
pub const DT_DIR = abi_fs.DT_DIR;
pub const DT_REG = abi_fs.DT_REG;
pub const DT_CHR = abi_fs.DT_CHR;
pub const dirent64Reclen = abi_fs.dirent64Reclen;
pub const Dirent64Entry = abi_fs.Dirent64Entry;
pub const Dirent64Iterator = abi_fs.Dirent64Iterator;
pub const writeDirent64 = abi_fs.writeDirent64;

pub fn open(path: [*:0]const u8, flags: u32, mode: u32) Result {
    return @intCast(syscall.open(path, flags, mode));
}

pub fn close(fd: Descriptor) Result {
    return @intCast(syscall.close(fd));
}

pub fn read(fd: Descriptor, buf: [*]u8, count: usize) Result {
    return @intCast(syscall.read(fd, buf, count));
}

pub fn write(fd: Descriptor, buf: [*]const u8, count: usize) Result {
    return @intCast(syscall.write(fd, buf, count));
}

/// Create a pair of connected descriptor endpoints.
pub fn pipe(endpoints: *[2]i32) Result {
    return @intCast(syscall.pipe(endpoints));
}

pub fn duplicate(fd: Descriptor) Result {
    return @intCast(syscall.dup(fd));
}

pub fn duplicateTo(source: Descriptor, target: Descriptor) Result {
    return @intCast(syscall.dup2(source, target));
}

pub fn stat(path: [*:0]const u8, out: *Stat) Result {
    return @intCast(syscall.stat(path, out));
}

pub fn getdents64(fd: Descriptor, buf: [*]u8, count: usize) Result {
    return @intCast(syscall.getdents64(fd, buf, count));
}

pub fn unlink(path: [*:0]const u8) Result {
    return @intCast(syscall.unlink(path));
}

pub fn rename(old_path: [*:0]const u8, new_path: [*:0]const u8) Result {
    return @intCast(syscall.rename(old_path, new_path));
}

pub fn symlink(target: [*:0]const u8, linkpath: [*:0]const u8) Result {
    return @intCast(syscall.symlink(target, linkpath));
}

pub fn readlink(path: [*:0]const u8, buf: [*]u8, bufsiz: usize) Result {
    return @intCast(syscall.readlink(path, buf, bufsiz));
}

pub fn mkdir(path: [*:0]const u8, mode: u32) Result {
    return @intCast(syscall.mkdir(path, mode));
}

pub fn rmdir(path: [*:0]const u8) Result {
    return @intCast(syscall.rmdir(path));
}

pub fn mount(
    source: ?[*:0]const u8,
    target: [*:0]const u8,
    fstype: [*:0]const u8,
    flags: u64,
    data: ?[*:0]const u8,
) Result {
    return @intCast(syscall.mount(source, target, fstype, flags, data));
}

pub fn umount(target: [*:0]const u8) Result {
    return @intCast(syscall.umount2(target, 0));
}

pub fn getcwd(buf: [*]u8, size: usize) Result {
    return @intCast(syscall.getcwd(buf, size));
}

pub fn chdir(path: [*:0]const u8) Result {
    return @intCast(syscall.chdir(path));
}

pub fn isDir(mode: u32) bool {
    return mode & S_IFDIR != 0;
}
