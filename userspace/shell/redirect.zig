const std = @import("std");
const ulib = @import("ulib");

pub const max_redirects = 4;
pub const max_filename_len = 128;

pub const Kind = enum {
    stdout_trunc,
    stdout_append,
    stderr_trunc,
    stderr_append,
    stderr_to_stdout,
    stdin,
};

pub const Redirect = struct {
    kind: Kind,
    filename: [max_filename_len]u8 = undefined,
    filename_len: usize = 0,

    pub fn filenameSlice(self: *const Redirect) []const u8 {
        return self.filename[0..self.filename_len];
    }
};

pub const ParseRedirects = struct {
    redirects: [max_redirects]Redirect = undefined,
    count: usize = 0,
};

/// Extract redirect tokens from the command segment and remove them from the line.
/// Mutates segment in-place (zeroes out redirect parts; caller should trim trailing NULs).
pub fn extract(segment: []u8, out: *ParseRedirects) error{ TooManyRedirects, FilenameTooLong }!void {
    out.count = 0;
    var i: usize = 0;
    while (i < segment.len) {
        if (isQuotedAt(segment, i)) {
            i += 1;
            continue;
        }

        const kind = matchRedirect(segment, i) orelse {
            i += 1;
            continue;
        };

        const op_len = redirectOpLen(kind);
        const arg_start = skipSpaces(segment, i + op_len);

        if (kind == .stderr_to_stdout) {
            // 2>&1 — just record and remove, no filename
            if (out.count >= max_redirects) return error.TooManyRedirects;
            out.redirects[out.count] = .{ .kind = kind };
            out.count += 1;
            removeRange(segment, i, arg_start);
            continue;
        }

        // Extract filename argument
        const arg_end = scanArg(segment, arg_start);
        if (arg_end == arg_start) {
            // No filename after redirect operator — skip
            i += 1;
            continue;
        }

        if (out.count >= max_redirects) return error.TooManyRedirects;

        const filename = segment[arg_start..arg_end];
        // Leave room for a trailing NUL used by open() as a C string.
        if (filename.len >= max_filename_len) return error.FilenameTooLong;
        var redir = Redirect{ .kind = kind };
        @memcpy(redir.filename[0..filename.len], filename);
        redir.filename[filename.len] = 0;
        redir.filename_len = filename.len;
        out.redirects[out.count] = redir;
        out.count += 1;

        removeRange(segment, i, arg_end);
    }
}

fn matchRedirect(segment: []const u8, pos: usize) ?Kind {
    if (pos + 1 >= segment.len) return null;

    // Check for 2>&1
    if (segment[pos] == '2' and pos + 3 <= segment.len) {
        if (std.mem.eql(u8, segment[pos .. pos + 3], "2>&")) {
            if (pos + 4 <= segment.len and segment[pos + 3] == '1') {
                return .stderr_to_stdout;
            }
        }
        // 2> or 2>>
        if (pos + 2 <= segment.len and std.mem.eql(u8, segment[pos .. pos + 2], "2>")) {
            if (pos + 3 <= segment.len and segment[pos + 2] == '>') return .stderr_append;
            return .stderr_trunc;
        }
    }

    // >>
    if (std.mem.eql(u8, segment[pos .. @min(pos + 2, segment.len)], ">>")) {
        return .stdout_append;
    }

    // >
    if (segment[pos] == '>') {
        return .stdout_trunc;
    }

    // <
    if (segment[pos] == '<') {
        return .stdin;
    }

    return null;
}

fn redirectOpLen(kind: Kind) usize {
    return switch (kind) {
        .stdout_trunc => 1,
        .stdout_append => 2,
        .stderr_trunc => 2,
        .stderr_append => 3,
        .stderr_to_stdout => 4,
        .stdin => 1,
    };
}

fn skipSpaces(segment: []const u8, start: usize) usize {
    var i = start;
    while (i < segment.len and segment[i] == ' ') i += 1;
    return i;
}

fn scanArg(segment: []const u8, start: usize) usize {
    var i = start;
    while (i < segment.len) : (i += 1) {
        if (segment[i] == ' ') break;
        if (segment[i] == '>' or segment[i] == '<') break;
        if (segment[i] == ';' or segment[i] == '&' or segment[i] == '|') break;
    }
    return i;
}

fn removeRange(segment: []u8, start: usize, end: usize) void {
    if (end > segment.len or start > end) return;
    const tail = segment.len - end;
    // Overlapping move: src is after dst.
    std.mem.copyForwards(u8, segment[start..][0..tail], segment[end..][0..tail]);
    @memset(segment[start + tail ..], 0);
}

fn isQuotedAt(buf: []const u8, pos: usize) bool {
    var in_quote = false;
    var i: usize = 0;
    while (i < pos) : (i += 1) {
        if (buf[i] == '"') in_quote = !in_quote;
    }
    return in_quote;
}

/// Apply redirects in a forked child process before exec.
pub fn apply(redirects: []const Redirect) void {
    for (redirects) |*redir| {
        switch (redir.kind) {
            .stdout_trunc => {
                const fd = ulib.fs.open(
                    @ptrCast(&redir.filename),
                    ulib.fs.O_CREAT | ulib.fs.O_WRONLY | ulib.fs.O_TRUNC,
                    0o644,
                );
                if (fd >= 0) {
                    _ = ulib.fs.duplicateTo(@intCast(fd), 1);
                    _ = ulib.fs.close(@intCast(fd));
                }
            },
            .stdout_append => {
                const fd = ulib.fs.open(
                    @ptrCast(&redir.filename),
                    ulib.fs.O_CREAT | ulib.fs.O_WRONLY | ulib.fs.O_APPEND,
                    0o644,
                );
                if (fd >= 0) {
                    _ = ulib.fs.duplicateTo(@intCast(fd), 1);
                    _ = ulib.fs.close(@intCast(fd));
                }
            },
            .stderr_trunc => {
                const fd = ulib.fs.open(
                    @ptrCast(&redir.filename),
                    ulib.fs.O_CREAT | ulib.fs.O_WRONLY | ulib.fs.O_TRUNC,
                    0o644,
                );
                if (fd >= 0) {
                    _ = ulib.fs.duplicateTo(@intCast(fd), 2);
                    _ = ulib.fs.close(@intCast(fd));
                }
            },
            .stderr_append => {
                const fd = ulib.fs.open(
                    @ptrCast(&redir.filename),
                    ulib.fs.O_CREAT | ulib.fs.O_WRONLY | ulib.fs.O_APPEND,
                    0o644,
                );
                if (fd >= 0) {
                    _ = ulib.fs.duplicateTo(@intCast(fd), 2);
                    _ = ulib.fs.close(@intCast(fd));
                }
            },
            .stderr_to_stdout => {
                _ = ulib.fs.duplicateTo(1, 2);
            },
            .stdin => {
                const fd = ulib.fs.open(
                    @ptrCast(&redir.filename),
                    ulib.fs.O_RDONLY,
                    0,
                );
                if (fd >= 0) {
                    _ = ulib.fs.duplicateTo(@intCast(fd), 0);
                    _ = ulib.fs.close(@intCast(fd));
                }
            },
        }
    }
}

var saved: ParseRedirects = .{};
var has_saved: bool = false;

/// Store parsed redirects for later application in the child process.
pub fn store(parsed: *const ParseRedirects) void {
    saved = parsed.*;
    has_saved = true;
}

/// Apply stored redirects (called in the child process before exec).
pub fn applyStored() void {
    if (!has_saved) return;
    has_saved = false;
    apply(saved.redirects[0..saved.count]);
}

/// Drop any stored redirects without applying them.
pub fn clearStored() void {
    has_saved = false;
    saved.count = 0;
}
