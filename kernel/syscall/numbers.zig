/// Linux-compatible x86_64 syscall numbers (initial subset).
pub const read = 0;
pub const write = 1;
pub const open = 2;
pub const close = 3;
pub const stat = 4;
pub const lseek = 8;
pub const brk = 12;
pub const getpid = 39;
pub const fork = 57;
pub const execve = 59;
pub const exit = 60;
pub const wait4 = 61;
pub const unlink = 87;
pub const mkdir = 83;
pub const rmdir = 84;
pub const exit_group = 231;
/// OS-specific: list directory entries (newline-separated) into a user buffer.
pub const listdir = 549;
