const io = @import("../io.zig");
const libc = @import("libc");

const bin_dir = "/BIN/";

/// Path/argv in .bss so fork+exec does not rely on a parent stack frame.
var exec_path: [128]u8 = undefined;
var exec_argv: [2]?[*:0]const u8 = .{ null, null };
var exec_envp: [1]?[*:0]const u8 = .{null};

pub fn run(name: []const u8) void {
    if (!formatBinPath(name, &exec_path)) {
        io.writeStr("spawn failed\n");
        return;
    }

    const my_pid = libc.syscall.getpid();
    const child = libc.syscall.fork();
    if (child < 0) {
        io.writeStr("spawn failed\n");
        return;
    }

    // After fork the child resumes with a copied stack; compare getpid() to the
    // pid we had before fork instead of relying on the fork return value alone.
    if (libc.syscall.getpid() != my_pid) {
        exec_argv[0] = @ptrCast(&exec_path);
        exec_argv[1] = null;
        _ = libc.syscall.execve(@ptrCast(&exec_path), @ptrCast(&exec_argv), @ptrCast(&exec_envp));
        libc.syscall.exit(1);
    }

    var status: u32 = 0;
    if (libc.syscall.waitpid(child, &status, 0) < 0) {
        io.writeStr("spawn failed\n");
    }
}

fn toUpper(ch: u8) u8 {
    if (ch >= 'a' and ch <= 'z') return ch - 32;
    return ch;
}

/// Map a shell command name to `/BIN/NAME` (FAT 8.3 names are uppercase).
/// There is no PATH yet — programs must live under /BIN on the disk.
fn formatBinPath(name: []const u8, out: []u8) bool {
    var i: usize = 0;
    for (bin_dir) |ch| {
        if (i >= out.len - 1) return false;
        out[i] = ch;
        i += 1;
    }
    for (name) |ch| {
        if (ch == ' ' or ch == '/') return false;
        if (i >= out.len - 1) return false;
        out[i] = toUpper(ch);
        i += 1;
    }
    if (i == bin_dir.len) return false;
    out[i] = 0;
    return true;
}
