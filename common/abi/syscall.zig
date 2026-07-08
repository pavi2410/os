/// Linux-compatible x86_64 syscall numbers used by both kernel and userspace.
pub const read = 0;
pub const write = 1;
pub const open = 2;
pub const close = 3;
pub const stat = 4;
pub const lseek = 8;
pub const brk = 12;
pub const pipe = 22;
pub const dup = 32;
pub const dup2 = 33;
pub const getpid = 39;
pub const socket = 41;
pub const connect = 42;
pub const sendto = 44;
pub const recvfrom = 45;
pub const send = 46;
pub const recv = 47;
pub const bind = 49;
pub const fork = 57;
pub const execve = 59;
pub const exit = 60;
pub const wait4 = 61;
pub const getcwd = 79;
pub const chdir = 80;
pub const mkdir = 83;
pub const rmdir = 84;
pub const unlink = 87;
pub const getdents64 = 217;
pub const clock_gettime = 228;
pub const exit_group = 231;

/// OS-specific inspection syscalls.
pub const getnetconfig = 1024;
pub const getneighbors = 1025;
pub const getcpuinfo = 1026;
pub const getpcidevices = 1027;
pub const getblockdevices = 1028;
pub const getmemregions = 1029;

pub const CLOCK_REALTIME: u32 = 0;
pub const CLOCK_MONOTONIC: u32 = 1;

pub const errno = struct {
    pub const perm: i64 = 1;
    pub const noent: i64 = 2;
    pub const intr: i64 = 4;
    pub const io: i64 = 5;
    pub const badf: i64 = 9;
    pub const acces: i64 = 13;
    pub const fault: i64 = 14;
    pub const inval: i64 = 22;
    pub const mfile: i64 = 24;
    pub const nosys: i64 = 38;

    pub fn negative(code: i64) i64 {
        return -code;
    }
};
