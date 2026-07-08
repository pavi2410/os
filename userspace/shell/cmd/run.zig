const argv_mod = @import("../argv.zig");
const environ = @import("../environ.zig");
const io = @import("../io.zig");
const path = @import("../path.zig");
const status = @import("../status.zig");
const ulib = @import("ulib");

var exec_path: [128]u8 = undefined;
var exec_arg_bufs: [argv_mod.max_args][128]u8 = undefined;
var exec_argv: [argv_mod.max_args + 1]?[*:0]const u8 = .{null} ** (argv_mod.max_args + 1);
var exec_envp: [environ.max_entries + 1]?[*:0]const u8 = .{null} ** (environ.max_entries + 1);

pub fn run(parsed: *const argv_mod.Parsed) u8 {
    const cmd = parsed.cmd() orelse return 0;
    if (!resolveExecutable(cmd, &exec_path)) {
        io.writeStr("run failed\n");
        return 127;
    }

    const my_pid = ulib.process.getpid();
    const child = ulib.process.fork();
    if (child < 0) {
        io.writeStr("run failed\n");
        return 1;
    }

    if (ulib.process.getpid() != my_pid) {
        const argc = buildArgv(parsed) orelse {
            ulib.process.exit(1);
        };
        exec_argv[argc] = null;
        environ.fillExecEnvp(&exec_envp);
        _ = ulib.process.execve(@ptrCast(&exec_path), @ptrCast(&exec_argv), @ptrCast(&exec_envp));
        ulib.process.exit(1);
    }

    var wstatus: u32 = 0;
    if (ulib.process.waitpid(child, &wstatus, 0) < 0) {
        io.writeStr("run failed\n");
        return 1;
    }
    return status.codeFromWait(wstatus);
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

fn resolveExecutable(name: []const u8, out: []u8) bool {
    if (name.len == 0) return false;
    if (name[0] == '/' or (name.len >= 2 and name[0] == '.' and name[1] == '/')) {
        return resolvePath(name, out);
    }
    return lookupInPath(name, out);
}

fn resolvePath(input: []const u8, out: []u8) bool {
    const resolved = path.resolve(input, out) orelse return false;
    return isExecutable(resolved);
}

fn lookupInPath(name: []const u8, out: []u8) bool {
    const path_value = environ.getValue("PATH") orelse "/BIN";
    var start: usize = 0;
    while (start <= path_value.len) {
        const end = colonEnd(path_value, start);
        const dir = path_value[start..end];
        if (dir.len > 0 and tryCandidate(dir, name, out)) return true;
        if (end >= path_value.len) break;
        start = end + 1;
    }
    return false;
}

fn colonEnd(path_value: []const u8, start: usize) usize {
    var i = start;
    while (i < path_value.len and path_value[i] != ':') : (i += 1) {}
    return i;
}

fn tryCandidate(dir: []const u8, name: []const u8, out: []u8) bool {
    var fat_name: [64]u8 = undefined;
    if (name.len > fat_name.len) return false;
    var i: usize = 0;
    while (i < name.len) : (i += 1) {
        fat_name[i] = toUpper(name[i]);
    }
    const candidate = ulib.path.join(dir, fat_name[0..name.len], out) catch return false;
    return isExecutable(candidate);
}

fn isExecutable(path_str: []const u8) bool {
    var st: ulib.fs.Stat = .{};
    if (ulib.fs.stat(@ptrCast(path_str.ptr), &st) < 0) return false;
    return st.st_mode & ulib.fs.S_IFREG != 0;
}

fn toUpper(ch: u8) u8 {
    if (ch >= 'a' and ch <= 'z') return ch - 32;
    return ch;
}
