const argv = @import("argv.zig");
const io = @import("io.zig");
const status = @import("status");
const ulib = @import("ulib");

const max_pipes = 4;

const PartRange = struct {
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
    var i: usize = 0;
    while (i < pipe_count) : (i += 1) {
        if (ulib.syscall.pipe(&pipe_fds[i]) < 0) {
            io.writeStr("pipe failed\n");
            return 1;
        }
    }

    var pids: [max_pipes + 1]isize = undefined;

    i = 0;
    while (i < cmd_count) : (i += 1) {
        const pid = ulib.process.fork();
        if (pid < 0) {
            io.writeStr("fork failed\n");
            return 1;
        }

        if (pid == 0) {
            if (i > 0) {
                _ = ulib.syscall.dup2(@intCast(pipe_fds[i - 1][0]), 0);
            }
            if (i < pipe_count) {
                _ = ulib.syscall.dup2(@intCast(pipe_fds[i][1]), 1);
            }

            var j: usize = 0;
            while (j < pipe_count) : (j += 1) {
                _ = ulib.syscall.close(@intCast(pipe_fds[j][0]));
                _ = ulib.syscall.close(@intCast(pipe_fds[j][1]));
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

            _ = ulib.process.execve(@ptrCast(&exec_path), @ptrCast(&exec_argv), @ptrCast(&[_]?[*:0]const u8{null}));
            ulib.process.exit(1);
        }

        pids[i] = pid;
    }

    var j: usize = 0;
    while (j < pipe_count) : (j += 1) {
        _ = ulib.syscall.close(@intCast(pipe_fds[j][0]));
        _ = ulib.syscall.close(@intCast(pipe_fds[j][1]));
    }

    var exit_code: u8 = 0;
    var k: usize = 0;
    while (k < cmd_count) : (k += 1) {
        var wstatus: u32 = 0;
        _ = ulib.process.waitpid(pids[k], &wstatus, 0);
        if (k == cmd_count - 1) {
            exit_code = status.codeFromWait(wstatus);
        }
    }

    return exit_code;
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
        if (name.len > out.len) return false;
        @memcpy(out[0..name.len], name);
        out[name.len] = 0;
        return true;
    }
    const prefix = "/BIN/";
    if (prefix.len + name.len > out.len) return false;
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
