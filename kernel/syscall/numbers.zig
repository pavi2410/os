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
pub const exit = 60;
pub const exit_group = 231;
/// OS-specific: run an embedded program and wait for it to exit.
pub const spawn = 548;
/// OS-specific: list directory entries (newline-separated) into a user buffer.
pub const listdir = 549;
