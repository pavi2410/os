const argv = @import("argv.zig");
const expand = @import("expand.zig");
const io = @import("io.zig");
const prefix_env = @import("prefix_env.zig");
const registry = @import("cmd/registry.zig");

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

const Op = enum { and_op, or_op };

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
    while (i < part_count) : (i += 1) {
        if (i > 0) {
            switch (ops[i - 1]) {
                .and_op => if (exit_code != 0) continue,
                .or_op => if (exit_code == 0) continue,
            }
        }

        const range = part_ranges[i];
        const cmd_len = trimSegment(segment, range.start, range.end);
        if (cmd_len <= range.start) continue;
        exit_code = executeCommand(segment[range.start..cmd_len], expand_bufs);
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
    if (i + 1 < segment.len and segment[i] == '|' and segment[i + 1] == '|') return .or_op;
    return null;
}

fn operatorLen(op: Op) usize {
    return switch (op) {
        .and_op, .or_op => 2,
    };
}

fn executeCommand(segment: []u8, expand_bufs: *[argv.max_args][expand.max_arg_len]u8) u8 {
    var parsed = argv.parse(segment, segment.len) catch {
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
