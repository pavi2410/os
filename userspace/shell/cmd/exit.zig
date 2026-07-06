const libc = @import("libc");

pub fn run() void {
    libc.process.exit(0);
}
