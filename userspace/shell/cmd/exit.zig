const libc = @import("libc");

pub fn run() void {
    libc.syscall.exit(0);
}
