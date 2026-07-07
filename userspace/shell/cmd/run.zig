const argv_mod = @import("../argv.zig");
const io = @import("../io.zig");
const ulib = @import("ulib");

const bin_dir = "/BIN/";

/// Path/argv in .bss so fork+exec does not rely on a parent stack frame.
var exec_path: [128]u8 = undefined;
var exec_arg_bufs: [argv_mod.max_args][128]u8 = undefined;
var exec_argv: [argv_mod.max_args + 1]?[*:0]const u8 = .{null} ** (argv_mod.max_args + 1);
var exec_envp: [1]?[*:0]const u8 = .{null};

pub fn run(parsed: *const argv_mod.Parsed) void {
    const cmd = parsed.cmd() orelse return;
    if (!formatBinPath(cmd, &exec_path)) {
        io.writeStr("run failed\n");
        return;
    }

    const my_pid = ulib.process.getpid();
    const child = ulib.process.fork();
    if (child < 0) {
        io.writeStr("run failed\n");
        return;
    }

    if (ulib.process.getpid() != my_pid) {
        const argc = buildArgv(parsed) orelse {
            ulib.process.exit(1);
        };
        exec_argv[argc] = null;
        _ = ulib.process.execve(@ptrCast(&exec_path), @ptrCast(&exec_argv), @ptrCast(&exec_envp));
        ulib.process.exit(1);
    }

    var status: u32 = 0;
    if (ulib.process.waitpid(child, &status, 0) < 0) {
        io.writeStr("run failed\n");
    }
}

fn buildArgv(parsed: *const argv_mod.Parsed) ?usize {
    exec_argv[0] = @ptrCast(&exec_path);
    var argc: usize = 1;

    var i: usize = 1;
    while (i < parsed.argc) : (i += 1) {
        if (argc >= exec_argv.len - 1) return null;
        const arg = parsed.args[i];
        if (arg.len >= exec_arg_bufs[0].len) return null;
        @memcpy(exec_arg_bufs[argc - 1][0..arg.len], arg);
        exec_arg_bufs[argc - 1][arg.len] = 0;
        exec_argv[argc] = @ptrCast(&exec_arg_bufs[argc - 1]);
        argc += 1;
    }
    return argc;
}

fn toUpper(ch: u8) u8 {
    if (ch >= 'a' and ch <= 'z') return ch - 32;
    return ch;
}

/// Map a shell command name to `/BIN/NAME` (FAT 8.3 names are uppercase).
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
