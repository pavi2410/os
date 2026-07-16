/// Freestanding Linux x86_64 syscall wrappers for user programs.
const abi_syscall = @import("abi_syscall");
const abi_fs = @import("abi_fs");
const abi_net = @import("abi_net");
const abi_hw = @import("abi_hw");

pub fn exit(status: u32) noreturn {
    _ = syscall6(abi_syscall.exit, status, 0, 0, 0, 0, 0);
    unreachable;
}

pub fn write(fd: u32, buf: [*]const u8, count: usize) isize {
    return syscall6(abi_syscall.write, fd, @intFromPtr(buf), count, 0, 0, 0);
}

pub fn read(fd: u32, buf: [*]u8, count: usize) isize {
    return syscall6(abi_syscall.read, fd, @intFromPtr(buf), count, 0, 0, 0);
}

pub fn open(path: [*:0]const u8, flags: u32, mode: u32) isize {
    return syscall6(abi_syscall.open, @intFromPtr(path), flags, mode, 0, 0, 0);
}

pub fn close(fd: u32) isize {
    return syscall6(abi_syscall.close, fd, 0, 0, 0, 0, 0);
}

pub fn pipe(fds: *[2]i32) isize {
    return syscall6(abi_syscall.pipe, @intFromPtr(fds), 0, 0, 0, 0, 0);
}

pub fn dup(old_fd: u32) isize {
    return syscall6(abi_syscall.dup, old_fd, 0, 0, 0, 0, 0);
}

pub fn dup2(old_fd: u32, new_fd: u32) isize {
    return syscall6(abi_syscall.dup2, old_fd, new_fd, 0, 0, 0, 0);
}

pub fn lseek(fd: u32, offset: i64, whence: u32) isize {
    return syscall6(abi_syscall.lseek, fd, @bitCast(@as(u64, @intCast(offset))), whence, 0, 0, 0);
}

pub const Stat = abi_fs.Stat;

pub fn stat(path: [*:0]const u8, out: *Stat) isize {
    return syscall6(abi_syscall.stat, @intFromPtr(path), @intFromPtr(out), 0, 0, 0, 0);
}

pub fn getpid() isize {
    return syscall6(abi_syscall.getpid, 0, 0, 0, 0, 0, 0);
}

pub fn fork() isize {
    return syscall6(abi_syscall.fork, 0, 0, 0, 0, 0, 0);
}

pub fn brk(addr: usize) isize {
    return syscall6(abi_syscall.brk, addr, 0, 0, 0, 0, 0);
}

pub fn getdents64(fd: u32, buf: [*]u8, count: usize) isize {
    return syscall6(abi_syscall.getdents64, fd, @intFromPtr(buf), count, 0, 0, 0);
}

pub const CLOCK_REALTIME = abi_syscall.CLOCK_REALTIME;
pub const CLOCK_MONOTONIC = abi_syscall.CLOCK_MONOTONIC;

pub const Timespec = extern struct {
    tv_sec: i64,
    tv_nsec: i64,
};

pub fn clock_gettime(clock_id: u32, out: *Timespec) isize {
    return syscall6(abi_syscall.clock_gettime, clock_id, @intFromPtr(out), 0, 0, 0, 0);
}

pub fn execve(path: [*:0]const u8, argv: [*:null]?[*:0]const u8, envp: [*:null]?[*:0]const u8) isize {
    return syscall6(abi_syscall.execve, @intFromPtr(path), @intFromPtr(argv), @intFromPtr(envp), 0, 0, 0);
}

pub const AF_INET = abi_net.AF_INET;
pub const SOCK_DGRAM = abi_net.SOCK_DGRAM;
pub const SOCK_STREAM = abi_net.SOCK_STREAM;
pub const IPPROTO_ICMP: u32 = @intCast(abi_net.IPPROTO_ICMP);
pub const IPPROTO_TCP: u32 = @intCast(abi_net.IPPROTO_TCP);
pub const IPPROTO_UDP: u32 = @intCast(abi_net.IPPROTO_UDP);

pub const SockaddrIn = abi_net.SockaddrIn;

pub fn socket(domain: u32, sock_type: u32, protocol: u32) isize {
    return syscall6(abi_syscall.socket, domain, sock_type, protocol, 0, 0, 0);
}

pub fn bind(fd: u32, addr: *const SockaddrIn, addrlen: u32) isize {
    return syscall6(abi_syscall.bind, fd, @intFromPtr(addr), addrlen, 0, 0, 0);
}

pub fn connect(fd: u32, addr: *const SockaddrIn, addrlen: u32) isize {
    return syscall6(abi_syscall.connect, fd, @intFromPtr(addr), addrlen, 0, 0, 0);
}

pub fn send(fd: u32, buf: [*]const u8, len: usize, flags: u32) isize {
    return syscall6(abi_syscall.send, fd, @intFromPtr(buf), len, flags, 0, 0);
}

pub fn recv(fd: u32, buf: [*]u8, len: usize, flags: u32) isize {
    return syscall6(abi_syscall.recv, fd, @intFromPtr(buf), len, flags, 0, 0);
}

pub fn sendto(
    fd: u32,
    buf: [*]const u8,
    len: usize,
    flags: u32,
    dest: *const SockaddrIn,
    addrlen: u32,
) isize {
    return syscall6(abi_syscall.sendto, fd, @intFromPtr(buf), len, flags, @intFromPtr(dest), addrlen);
}

pub fn recvfrom(
    fd: u32,
    buf: [*]u8,
    len: usize,
    flags: u32,
    src: ?*SockaddrIn,
    addrlen: ?*u32,
) isize {
    const src_ptr: u64 = if (src) |s| @intFromPtr(s) else 0;
    const alen_ptr: u64 = if (addrlen) |a| @intFromPtr(a) else 0;
    return syscall6(abi_syscall.recvfrom, fd, @intFromPtr(buf), len, flags, src_ptr, alen_ptr);
}

pub const NetConfig = abi_net.NetConfig;
pub const NeighEntry = abi_net.NeighEntry;

pub fn getnetconfig(out: *NetConfig) isize {
    return syscall6(abi_syscall.getnetconfig, @intFromPtr(out), 0, 0, 0, 0, 0);
}

pub fn getneighbors(buf: [*]NeighEntry, max: usize) isize {
    return syscall6(abi_syscall.getneighbors, @intFromPtr(buf), max, 0, 0, 0, 0);
}

pub const CpuInfo = abi_hw.CpuInfo;
pub const PciDeviceInfo = abi_hw.PciDeviceInfo;
pub const BlockDeviceInfo = abi_hw.BlockDeviceInfo;
pub const MemRegionInfo = abi_hw.MemRegionInfo;

pub fn getcpuinfo(out: *CpuInfo) isize {
    return syscall6(abi_syscall.getcpuinfo, @intFromPtr(out), 0, 0, 0, 0, 0);
}

pub fn getpcidevices(buf: [*]PciDeviceInfo, max: usize) isize {
    return syscall6(abi_syscall.getpcidevices, @intFromPtr(buf), max, 0, 0, 0, 0);
}

pub fn getblockdevices(buf: [*]BlockDeviceInfo, max: usize) isize {
    return syscall6(abi_syscall.getblockdevices, @intFromPtr(buf), max, 0, 0, 0, 0);
}

pub fn getmemregions(buf: [*]MemRegionInfo, max: usize) isize {
    return syscall6(abi_syscall.getmemregions, @intFromPtr(buf), max, 0, 0, 0, 0);
}

pub fn waitpid(pid: isize, status: ?*u32, options: u32) isize {
    const status_ptr: u64 = if (status) |s| @intFromPtr(s) else 0;
    const pid_arg: u64 = @bitCast(@as(i64, pid));
    return syscall6(abi_syscall.wait4, pid_arg, status_ptr, options, 0, 0, 0);
}

pub fn unlink(path: [*:0]const u8) isize {
    return syscall6(abi_syscall.unlink, @intFromPtr(path), 0, 0, 0, 0, 0);
}

pub fn mkdir(path: [*:0]const u8, mode: u32) isize {
    return syscall6(abi_syscall.mkdir, @intFromPtr(path), mode, 0, 0, 0, 0);
}

pub fn rmdir(path: [*:0]const u8) isize {
    return syscall6(abi_syscall.rmdir, @intFromPtr(path), 0, 0, 0, 0, 0);
}

pub fn getcwd(buf: [*]u8, size: usize) isize {
    return syscall6(abi_syscall.getcwd, @intFromPtr(buf), size, 0, 0, 0, 0);
}

pub fn chdir(path: [*:0]const u8) isize {
    return syscall6(abi_syscall.chdir, @intFromPtr(path), 0, 0, 0, 0, 0);
}

pub fn rtSigaction(signum: u32, act_ptr: u64, oldact_ptr: u64, sigsetsize: usize) isize {
    return syscall6(abi_syscall.rt_sigaction, signum, act_ptr, oldact_ptr, sigsetsize, 0, 0);
}

pub fn rtSigprocmask(how: u32, set_ptr: u64, oldset_ptr: u64, sigsetsize: usize) isize {
    return syscall6(abi_syscall.rt_sigprocmask, how, set_ptr, oldset_ptr, sigsetsize, 0, 0);
}

pub fn kill(pid: u64, signum: u32) isize {
    return syscall6(abi_syscall.kill, pid, signum, 0, 0, 0, 0);
}

fn syscall6(
    nr: u64,
    arg0: u64,
    arg1: u64,
    arg2: u64,
    arg3: u64,
    arg4: u64,
    arg5: u64,
) isize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> isize),
        : [nr] "{rax}" (nr),
          [arg0] "{rdi}" (arg0),
          [arg1] "{rsi}" (arg1),
          [arg2] "{rdx}" (arg2),
          [arg3] "{r10}" (arg3),
          [arg4] "{r8}" (arg4),
          [arg5] "{r9}" (arg5),
        : .{ .rcx = true, .r11 = true, .memory = true });
}

