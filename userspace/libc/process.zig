const syscall = @import("syscall.zig");

pub fn exit(status: u32) noreturn {
    syscall.exit(status);
}

pub fn getpid() isize {
    return syscall.getpid();
}

pub fn fork() isize {
    return syscall.fork();
}

pub fn execve(path: [*:0]const u8, argv: [*:null]?[*:0]const u8, envp: [*:null]?[*:0]const u8) isize {
    return syscall.execve(path, argv, envp);
}

pub fn waitpid(pid: isize, status: ?*u32, options: u32) isize {
    return syscall.waitpid(pid, status, options);
}
