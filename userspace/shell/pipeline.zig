const argv = @import("argv.zig");
const environ = @import("environ.zig");
const io = @import("io.zig");
const status = @import("status");
const ulib = @import("ulib");

const max_pipes = 4;

pub const PartRange = struct {
    start: usize,
    end: usize,
};

pub fn run(
    segment: []u8,
    parts: []const PartRange,
    part_count: usize,
    expand_bufs: *[argv.max_args][128]u8,
) u8 {
    _ = expand_bufs;
    if (part_count < 2 or part_count > max_pipes + 1) return 1;

    const cmd_count = part_count;
    const pipe_count = cmd_count - 1;

    var pipe_fds: [max_pipes][2]i32 = undefined;
    var pipes_created: usize = 0;
    var i: usize = 0;
    while (i < pipe_count) : (i += 1) {
        if (ulib.fs.pipe(&pipe_fds[i]) < 0) {
            closePipeEnds(pipe_fds[0..pipes_created]);
            io.writeStr("pipe failed\n");
            return 1;
        }
        pipes_created += 1;
    }

    var pids: [max_pipes + 1]ulib.process.ProcessId = undefined;
    var spawned: usize = 0;

    i = 0;
    while (i < cmd_count) : (i += 1) {
        const pid = ulib.process.fork();
        if (pid < 0) {
            closePipeEnds(pipe_fds[0..pipes_created]);
            waitSpawned(pids[0..spawned]);
            io.writeStr("fork failed\n");
            return 1;
        }

        if (pid == 0) {
            _ = ulib.signal.default(ulib.signal.SIGINT);
            if (i > 0) {
                _ = ulib.fs.duplicateTo(@intCast(pipe_fds[i - 1][0]), 0);
            }
            if (i < pipe_count) {
                _ = ulib.fs.duplicateTo(@intCast(pipe_fds[i][1]), 1);
            }

            var j: usize = 0;
            while (j < pipe_count) : (j += 1) {
                _ = ulib.fs.close(@intCast(pipe_fds[j][0]));
                _ = ulib.fs.close(@intCast(pipe_fds[j][1]));
            }

            const range = parts[i];
            const sub_len = trimSegment(segment, range.start, range.end);
            if (sub_len <= range.start) {
                ulib.process.exit(0);
            }

            var parsed = argv.parse(segment[range.start..sub_len], sub_len - range.start) catch {
                ulib.process.exit(1);
            };
            if (parsed.argc == 0) {
                ulib.process.exit(0);
            }

            const cmd = parsed.cmd() orelse {
                ulib.process.exit(0);
            };

            var exec_path: [128]u8 = undefined;
            if (!resolveExecutable(cmd, &exec_path)) {
                ulib.process.exit(127);
            }

            var exec_argv: [argv.max_args + 1]?[*:0]const u8 = .{null} ** (argv.max_args + 1);
            var exec_arg_bufs: [argv.max_args][128]u8 = undefined;
            exec_argv[0] = @ptrCast(&exec_path);
            var argc: usize = 1;
            var k: usize = 1;
            while (k < parsed.argc) : (k += 1) {
                if (argc >= exec_argv.len - 1) break;
                const arg = parsed.args[k];
                if (arg.len >= exec_arg_bufs[0].len) break;
                @memcpy(exec_arg_bufs[argc - 1][0..arg.len], arg);
                exec_arg_bufs[argc - 1][arg.len] = 0;
                exec_argv[argc] = @ptrCast(&exec_arg_bufs[argc - 1]);
                argc += 1;
            }
            exec_argv[argc] = null;

            var exec_envp: [environ.max_entries + 1]?[*:0]const u8 = .{null} ** (environ.max_entries + 1);
            environ.fillExecEnvp(&exec_envp);

            _ = ulib.process.exec(@ptrCast(&exec_path), @ptrCast(&exec_argv), @ptrCast(&exec_envp));
            ulib.process.exit(1);
        }

        pids[i] = pid;
        spawned += 1;
    }

    closePipeEnds(pipe_fds[0..pipes_created]);

    var exit_code: u8 = 0;
    var k: usize = 0;
    while (k < spawned) : (k += 1) {
        var wstatus: u32 = 0;
        _ = ulib.process.wait(pids[k], &wstatus, 0);
        if (k == spawned - 1) {
            exit_code = status.codeFromWait(wstatus);
        }
    }

    return exit_code;
}

fn closePipeEnds(pipes: [][2]i32) void {
    for (pipes) |ends| {
        _ = ulib.fs.close(@intCast(ends[0]));
        _ = ulib.fs.close(@intCast(ends[1]));
    }
}

fn waitSpawned(pids: []const ulib.process.ProcessId) void {
    for (pids) |pid| {
        var wstatus: u32 = 0;
        _ = ulib.process.wait(pid, &wstatus, 0);
    }
}

fn trimSegment(buf: []u8, start: usize, end: usize) usize {
    var s = start;
    while (s < end and buf[s] == ' ') s += 1;
    var e = end;
    while (e > s and buf[e - 1] == ' ') e -= 1;
    return e;
}

fn resolveExecutable(name: []const u8, out: []u8) bool {
    if (name.len == 0) return false;
    if (name[0] == '/') {
        if (name.len + 1 > out.len) return false;
        @memcpy(out[0..name.len], name);
        out[name.len] = 0;
        return true;
    }
    const prefix = "/BIN/";
    if (prefix.len + name.len + 1 > out.len) return false;
    @memcpy(out[0..prefix.len], prefix);
    var i: usize = 0;
    while (i < name.len) : (i += 1) {
        var ch = name[i];
        if (ch >= 'a' and ch <= 'z') ch -= 32;
        out[prefix.len + i] = ch;
    }
    out[prefix.len + name.len] = 0;
    return true;
}
