const std = @import("std");
const string = @import("string");

pub const default_cap = 256;

pub const ResolveError = error{
    PathTooLong,
};

const max_components = 16;
const max_name_len = 64;

/// Resolve `input` against `base` into `out` (NUL-terminated). Returns slice without NUL.
pub fn resolveAgainst(base: []const u8, input: []const u8, out: []u8) ResolveError![]const u8 {
    var names: [max_components][max_name_len]u8 = undefined;
    var lens: [max_components]usize = undefined;
    var count: usize = 0;

    const absolute = input.len > 0 and input[0] == '/';
    if (!absolute) {
        try collectComponents(base, &names, &lens, &count);
    }
    try collectComponents(input, &names, &lens, &count);
    return try emitPath(&names, &lens, count, out);
}

/// Join `dir` and `name` into `out` (NUL-terminated). Returns slice without NUL.
pub fn join(dir: []const u8, name: []const u8, out: []u8) ResolveError![]const u8 {
    if (dir.len == 0 or name.len == 0) return ResolveError.PathTooLong;

    var pos: usize = 0;
    if (std.mem.eql(u8, dir, "/")) {
        if (1 + name.len + 1 > out.len) return ResolveError.PathTooLong;
        out[0] = '/';
        pos = 1;
    } else {
        if (dir.len + 1 + name.len + 1 > out.len) return ResolveError.PathTooLong;
        @memcpy(out[0..dir.len], dir);
        out[dir.len] = '/';
        pos = dir.len + 1;
    }
    @memcpy(out[pos .. pos + name.len], name);
    out[pos + name.len] = 0;
    return out[0 .. pos + name.len];
}

/// Fixed-capacity VFS-style absolute path.
pub fn Path(comptime cap: usize) type {
    const Str = string.String(cap);

    return struct {
        str: Str,

        const Self = @This();

        pub const Error = Str.Error || ResolveError;

        pub fn empty() Self {
            return .{ .str = Str.empty() };
        }

        pub fn from(comptime literal: []const u8) Self {
            return .{ .str = Str.from(literal) };
        }

        pub fn root() Self {
            return from("/");
        }

        pub fn slice(self: *const Self) []const u8 {
            return self.str.slice();
        }

        pub fn capacity(self: *const Self) usize {
            return self.str.capacity();
        }

        pub fn bufPtr(self: *Self) [*]u8 {
            return self.str.bufPtr();
        }

        pub fn cPtr(self: *Self) [*:0]u8 {
            return self.str.cPtr();
        }

        pub fn set(self: *Self, data: []const u8) Error!void {
            return self.str.set(data);
        }

        pub fn setLen(self: *Self, n: usize) Error!void {
            return self.str.setLen(n);
        }

        pub fn eql(self: *const Self, other: []const u8) bool {
            return self.str.eql(other);
        }

        pub fn resolveFrom(self: *const Self, input: []const u8, out: *Self) Error!void {
            const resolved = resolveAgainst(self.slice(), input, out.str.buf[0..cap]) catch |err| return err;
            try out.str.setLen(resolved.len);
        }

        pub fn joinInto(dir: []const u8, name: []const u8, out: *Self) Error!void {
            const joined = join(dir, name, out.str.buf[0..cap]) catch |err| return err;
            try out.str.setLen(joined.len);
        }
    };
}

fn collectComponents(
    path: []const u8,
    names: *[max_components][max_name_len]u8,
    lens: *[max_components]usize,
    count: *usize,
) ResolveError!void {
    var i: usize = 0;
    if (path.len > 0 and path[0] == '/') i = 1;
    while (i <= path.len) {
        const start = i;
        while (i < path.len and path[i] != '/') i += 1;
        try applyComponent(path[start..i], names, lens, count);
        i += 1;
    }
}

fn applyComponent(
    comp: []const u8,
    names: *[max_components][max_name_len]u8,
    lens: *[max_components]usize,
    count: *usize,
) ResolveError!void {
    if (comp.len == 0) return;
    if (comp.len == 1 and comp[0] == '.') return;
    if (comp.len == 2 and comp[0] == '.' and comp[1] == '.') {
        if (count.* > 0) count.* -= 1;
        return;
    }
    if (comp.len > max_name_len or count.* >= max_components) return ResolveError.PathTooLong;
    @memcpy(names[count.*][0..comp.len], comp);
    lens[count.*] = comp.len;
    count.* += 1;
}

fn emitPath(
    names: *const [max_components][max_name_len]u8,
    lens: *const [max_components]usize,
    count: usize,
    out: []u8,
) ResolveError![]const u8 {
    if (count == 0) {
        if (out.len < 2) return ResolveError.PathTooLong;
        out[0] = '/';
        out[1] = 0;
        return out[0..1];
    }

    var pos: usize = 0;
    out[pos] = '/';
    pos += 1;

    var idx: usize = 0;
    while (idx < count) : (idx += 1) {
        const name = names[idx][0..lens[idx]];
        if (pos + name.len >= out.len) return ResolveError.PathTooLong;
        @memcpy(out[pos .. pos + name.len], name);
        pos += name.len;
        if (idx + 1 < count) {
            out[pos] = '/';
            pos += 1;
        }
    }
    if (pos + 1 > out.len) return ResolveError.PathTooLong;
    out[pos] = 0;
    return out[0..pos];
}
