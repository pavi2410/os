/// Freestanding Linux x86_64 syscall wrappers for user programs.
pub fn exit(status: u32) noreturn {
    _ = syscall6(60, status, 0, 0, 0, 0, 0);
    unreachable;
}

pub fn write(fd: u32, buf: [*]const u8, count: usize) isize {
    return syscall6(1, fd, @intFromPtr(buf), count, 0, 0, 0);
}

pub fn read(fd: u32, buf: [*]u8, count: usize) isize {
    return syscall6(0, fd, @intFromPtr(buf), count, 0, 0, 0);
}

pub fn open(path: [*:0]const u8, flags: u32, mode: u32) isize {
    return syscall6(2, @intFromPtr(path), flags, mode, 0, 0, 0);
}

pub fn close(fd: u32) isize {
    return syscall6(3, fd, 0, 0, 0, 0, 0);
}

pub fn lseek(fd: u32, offset: i64, whence: u32) isize {
    return syscall6(8, fd, @bitCast(@as(u64, @intCast(offset))), whence, 0, 0, 0);
}

pub fn getpid() isize {
    return syscall6(39, 0, 0, 0, 0, 0, 0);
}

pub fn brk(addr: usize) isize {
    return syscall6(12, addr, 0, 0, 0, 0, 0);
}

pub fn spawn(path: [*:0]const u8) isize {
    return syscall6(548, @intFromPtr(path), 0, 0, 0, 0, 0);
}

pub fn execve(path: [*:0]const u8, argv: [*:null]?[*:0]const u8, envp: [*:null]?[*:0]const u8) isize {
    return syscall6(59, @intFromPtr(path), @intFromPtr(argv), @intFromPtr(envp), 0, 0, 0);
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
