const argv = @import("argv.zig");
const expand = @import("expand.zig");
const io = @import("io.zig");
const prefix_env = @import("prefix_env.zig");
const redirect = @import("redirect.zig");
const registry = @import("cmd/registry.zig");
const ulib = @import("ulib");

/// Return effective line length after stripping an unquoted `#` comment.
pub fn stripComment(buf: []u8, len: usize) usize {
    var i: usize = 0;
    var in_double = false;
    var escape = false;

    while (i < len) : (i += 1) {
        const ch = buf[i];
        if (escape) {
            escape = false;
            continue;
        }
        if (in_double) {
            if (ch == '\\') {
                escape = true;
            } else if (ch == '"') {
                in_double = false;
            }
            continue;
        }
        if (ch == '"') {
            in_double = true;
            continue;
        }
        if (ch == '#') return trimTrailing(buf, i);
    }

    return trimTrailing(buf, len);
}

pub fn executeLine(buf: []u8, expand_bufs: *[argv.max_args][expand.max_arg_len]u8) void {
    const len = buf.len;
    var start: usize = 0;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        if (buf[i] == ';' and !isQuotedAt(buf, i)) {
            runSegment(buf[start..i], expand_bufs);
            start = i + 1;
        }
    }
    if (start < len) {
        runSegment(buf[start..len], expand_bufs);
    }
}

pub fn segmentCount(buf: []const u8, len: usize) usize {
    var count: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        if (buf[i] == ';' and !isQuotedAt(buf, i)) {
            if (trimSegment(buf, start, i) > start) count += 1;
            start = i + 1;
        }
    }
    if (trimSegment(buf, start, len) > start) count += 1;
    return count;
}

const Op = enum { and_op, or_op, pipe_op };

const max_chain_parts = 8;

const PartRange = struct {
    start: usize,
    end: usize,
};

pub fn chainPartCount(segment: []const u8) usize {
    var parts: [max_chain_parts]PartRange = undefined;
    var ops: [max_chain_parts - 1]Op = undefined;
    return splitByOperators(segment, &parts, &ops) catch 0;
}

fn runSegment(segment: []u8, expand_bufs: *[argv.max_args][expand.max_arg_len]u8) void {
    const trimmed_len = trimSegment(segment, 0, segment.len);
    if (trimmed_len == 0) return;

    var part_ranges: [max_chain_parts]PartRange = undefined;
    var ops: [max_chain_parts - 1]Op = undefined;
    const part_count = splitByOperators(segment[0..trimmed_len], &part_ranges, &ops) catch {
        io.writeStr("command chain too long\n");
        return;
    };
    if (part_count == 0) return;

    var exit_code: u8 = 0;
    var i: usize = 0;
    while (i < part_count) {
        if (i > 0) {
            switch (ops[i - 1]) {
                .and_op => if (exit_code != 0) {
                    i += 1;
                    continue;
                },
                .or_op => if (exit_code == 0) {
                    i += 1;
                    continue;
                },
                .pipe_op => {},
            }
        }

        var pipe_end = i;
        while (pipe_end + 1 < part_count and ops[pipe_end] == .pipe_op) {
            pipe_end += 1;
        }

        if (pipe_end > i) {
            exit_code = runPipeline(segment, part_ranges[i .. pipe_end + 1], expand_bufs);
            @import("status").set(exit_code);
            i = pipe_end + 1;
            continue;
        }

        const range = part_ranges[i];
        const cmd_len = trimSegment(segment, range.start, range.end);
        if (cmd_len > range.start) {
            exit_code = executeCommand(segment[range.start..cmd_len], expand_bufs);
        }
        i += 1;
    }
}

fn splitByOperators(
    segment: []const u8,
    parts: *[max_chain_parts]PartRange,
    ops: *[max_chain_parts - 1]Op,
) error{TooManyParts}!usize {
    var part_count: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i < segment.len) {
        if (matchOperator(segment, i)) |op| {
            if (part_count >= max_chain_parts) return error.TooManyParts;
            parts[part_count] = .{ .start = start, .end = i };
            part_count += 1;
            if (part_count - 1 >= ops.len) return error.TooManyParts;
            ops[part_count - 1] = op;
            i += operatorLen(op);
            start = i;
            continue;
        }
        i += 1;
    }

    if (part_count >= max_chain_parts) return error.TooManyParts;
    parts[part_count] = .{ .start = start, .end = segment.len };
    return part_count + 1;
}

fn matchOperator(segment: []const u8, i: usize) ?Op {
    if (isQuotedAt(segment, i)) return null;
    if (i + 1 < segment.len and segment[i] == '&' and segment[i + 1] == '&') return .and_op;
    if (i + 1 < segment.len and segment[i] == '|') {
        if (segment[i + 1] == '|') return .or_op;
        return .pipe_op;
    }
    return null;
}

fn operatorLen(op: Op) usize {
    return switch (op) {
        .and_op, .or_op => 2,
        .pipe_op => 1,
    };
}

fn executeCommand(segment: []u8, expand_bufs: *[argv.max_args][expand.max_arg_len]u8) u8 {
    var redirects: redirect.ParseRedirects = .{};
    redirect.extract(segment, &redirects) catch {
        io.writeStr("redirect failed\n");
        return 1;
    };
    var cmd_len = segment.len;
    while (cmd_len > 0 and segment[cmd_len - 1] == 0) cmd_len -= 1;
    while (cmd_len > 0 and segment[cmd_len - 1] == ' ') cmd_len -= 1;

    var saved_in: i64 = -1;
    var saved_out: i64 = -1;
    var saved_err: i64 = -1;
    if (redirects.count > 0) {
        saved_in = ulib.fs.duplicate(0);
        saved_out = ulib.fs.duplicate(1);
        saved_err = ulib.fs.duplicate(2);
        if (saved_in < 0 or saved_out < 0 or saved_err < 0) {
            io.writeStr("redirect failed\n");
            return 1;
        }
        redirect.store(&redirects);
        redirect.apply(redirects.redirects[0..redirects.count]);
    }
    defer {
        if (saved_in >= 0) {
            _ = ulib.fs.duplicateTo(@intCast(saved_in), 0);
            _ = ulib.fs.close(@intCast(saved_in));
        }
        if (saved_out >= 0) {
            _ = ulib.fs.duplicateTo(@intCast(saved_out), 1);
            _ = ulib.fs.close(@intCast(saved_out));
        }
        if (saved_err >= 0) {
            _ = ulib.fs.duplicateTo(@intCast(saved_err), 2);
            _ = ulib.fs.close(@intCast(saved_err));
        }
        redirect.clearStored();
    }

    var parsed = argv.parse(segment[0..cmd_len], cmd_len) catch {
        io.writeStr("too many arguments\n");
        return 1;
    };
    if (parsed.argc == 0) return 0;

    prefix_env.clear();
    if (!prefix_env.peel(&parsed)) {
        io.writeStr("invalid command\n");
        return 1;
    }

    if (!expand.expandArgvWith(&parsed, expand_bufs, prefix_env.lookup)) {
        io.writeStr("expansion failed\n");
        return 1;
    }

    const cmd = parsed.cmd() orelse return 0;
    return registry.dispatch(cmd, &parsed);
}

fn isQuotedAt(buf: []const u8, pos: usize) bool {
    var in_double = false;
    var escape = false;
    var i: usize = 0;
    while (i < pos) : (i += 1) {
        const ch = buf[i];
        if (escape) {
            escape = false;
            continue;
        }
        if (in_double) {
            if (ch == '\\') {
                escape = true;
            } else if (ch == '"') {
                in_double = false;
            }
            continue;
        }
        if (ch == '"') in_double = true;
    }
    return in_double;
}

fn trimSegment(buf: []const u8, start: usize, end: usize) usize {
    var s = start;
    while (s < end and buf[s] == ' ') s += 1;
    var e = end;
    while (e > s and buf[e - 1] == ' ') e -= 1;
    return e;
}

fn trimTrailing(buf: []u8, end: usize) usize {
    var len = end;
    while (len > 0 and buf[len - 1] == ' ') len -= 1;
    return len;
}

fn runPipeline(segment: []u8, parts: []const PartRange, expand_bufs: *[argv.max_args][expand.max_arg_len]u8) u8 {
    const pipeline = @import("pipeline.zig");
    var pipe_parts: [max_chain_parts]pipeline.PartRange = undefined;
    if (parts.len > pipe_parts.len) return 1;
    for (parts, 0..) |range, idx| {
        pipe_parts[idx] = .{ .start = range.start, .end = range.end };
    }
    // pipeline.run still uses [128]u8 expand buffers; C19 aligns sizes.
    var short_bufs: [argv.max_args][128]u8 = undefined;
    _ = expand_bufs;
    return pipeline.run(segment, pipe_parts[0..parts.len], parts.len, &short_bufs);
}
