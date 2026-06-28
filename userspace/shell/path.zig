const io = @import("io.zig");
const cwd = @import("cwd.zig");

const max_components = 16;
const max_name_len = 64;

pub fn resolve(input: []const u8, out: []u8) ?[]const u8 {
    if (!resolveAgainst(cwd.get(), input, out)) return null;
    var end: usize = 0;
    while (end < out.len and out[end] != 0) end += 1;
    return out[0..end];
}

pub fn resolveAgainst(base: []const u8, input: []const u8, out: []u8) bool {
    var names: [max_components][max_name_len]u8 = undefined;
    var lens: [max_components]usize = undefined;
    var count: usize = 0;

    const absolute = input.len > 0 and input[0] == '/';
    if (!absolute) {
        if (!collectComponents(base, &names, &lens, &count)) return false;
    }
    if (!collectComponents(input, &names, &lens, &count)) return false;
    return emitPath(&names, &lens, count, out);
}

fn collectComponents(
    path: []const u8,
    names: *[max_components][max_name_len]u8,
    lens: *[max_components]usize,
    count: *usize,
) bool {
    var i: usize = 0;
    if (path.len > 0 and path[0] == '/') i = 1;
    while (i <= path.len) {
        const start = i;
        while (i < path.len and path[i] != '/') i += 1;
        if (!applyComponent(path[start..i], names, lens, count)) return false;
        i += 1;
    }
    return true;
}

fn applyComponent(
    comp: []const u8,
    names: *[max_components][max_name_len]u8,
    lens: *[max_components]usize,
    count: *usize,
) bool {
    if (comp.len == 0) return true;
    if (comp.len == 1 and comp[0] == '.') return true;
    if (comp.len == 2 and comp[0] == '.' and comp[1] == '.') {
        if (count.* > 0) count.* -= 1;
        return true;
    }
    if (comp.len > max_name_len or count.* >= max_components) return false;
    @memcpy(names[count.*][0..comp.len], comp);
    lens[count.*] = comp.len;
    count.* += 1;
    return true;
}

fn emitPath(
    names: *const [max_components][max_name_len]u8,
    lens: *const [max_components]usize,
    count: usize,
    out: []u8,
) bool {
    if (count == 0) {
        if (out.len < 2) return false;
        out[0] = '/';
        out[1] = 0;
        return true;
    }

    var pos: usize = 0;
    out[pos] = '/';
    pos += 1;

    var idx: usize = 0;
    while (idx < count) : (idx += 1) {
        const name = names[idx][0..lens[idx]];
        if (pos + name.len >= out.len) return false;
        @memcpy(out[pos .. pos + name.len], name);
        pos += name.len;
        if (idx + 1 < count) {
            out[pos] = '/';
            pos += 1;
        }
    }
    if (pos >= out.len) return false;
    out[pos] = 0;
    return true;
}

pub fn join(dir: []const u8, name: []const u8, out: []u8) bool {
    if (dir.len == 0 or name.len == 0) return false;
    var len: usize = 0;
    if (io.eql(dir, "/")) {
        if (1 + name.len + 1 > out.len) return false;
        out[0] = '/';
        len = 1;
    } else {
        if (dir.len + 1 + name.len + 1 > out.len) return false;
        @memcpy(out[0..dir.len], dir);
        out[dir.len] = '/';
        len = dir.len + 1;
    }
    @memcpy(out[len .. len + name.len], name);
    out[len + name.len] = 0;
    return true;
}

pub fn copy(path: []const u8, out: []u8) bool {
    if (path.len + 1 > out.len) return false;
    @memcpy(out[0..path.len], path);
    out[path.len] = 0;
    return true;
}
