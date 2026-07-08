const cwd = @import("cwd.zig");
const string = @import("ulib").string;

pub const max_entries = 16;
pub const entry_max = 128;

var entries: [max_entries][entry_max]u8 = undefined;
var entry_lens: [max_entries]usize = undefined;
var count: usize = 0;

pub fn init() void {
    _ = setPair("PATH", "/BIN");
    _ = setPair("PWD", "/");
    _ = setPair("HOME", "/");
    _ = setPair("SHELL", "/BIN/SHELL");
}

pub fn countEntries() usize {
    return count;
}

pub fn entryAt(index: usize) []const u8 {
    return entries[index][0..entry_lens[index]];
}

pub fn getValue(name: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const entry = entryAt(i);
        if (entryMatchesName(entry, name)) {
            return valueAfterEq(entry);
        }
    }
    return null;
}

pub fn setLine(line: []const u8) bool {
    const eq = string.indexOfScalar(line, '=') orelse return false;
    if (eq == 0) return false;
    return setPair(line[0..eq], line[eq + 1 ..]);
}

pub fn setPair(key: []const u8, value: []const u8) bool {
    if (key.len == 0 or key.len + 1 + value.len >= entry_max) return false;

    if (findIndex(key)) |idx| {
        return writeEntry(idx, key, value);
    }
    if (count >= max_entries) return false;
    const ok = writeEntry(count, key, value);
    if (ok) count += 1;
    return ok;
}

pub fn syncPwd() void {
    _ = setPair("PWD", cwd.get());
}

pub fn unset(name: []const u8) bool {
    const idx = findIndex(name) orelse return false;
    var i = idx;
    while (i + 1 < count) : (i += 1) {
        entries[i] = entries[i + 1];
        entry_lens[i] = entry_lens[i + 1];
    }
    count -= 1;
    return true;
}

pub fn fillExecEnvp(out: *[max_entries + 1]?[*:0]const u8) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        out[i] = @ptrCast(&entries[i]);
    }
    out[count] = null;
}

fn findIndex(key: []const u8) ?usize {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (entryMatchesName(entryAt(i), key)) return i;
    }
    return null;
}

fn writeEntry(index: usize, key: []const u8, value: []const u8) bool {
    if (key.len + 1 + value.len >= entry_max) return false;
    var pos: usize = 0;
    @memcpy(entries[index][0..key.len], key);
    pos = key.len;
    entries[index][pos] = '=';
    pos += 1;
    @memcpy(entries[index][pos .. pos + value.len], value);
    pos += value.len;
    entries[index][pos] = 0;
    entry_lens[index] = pos;
    return true;
}

fn entryMatchesName(entry: []const u8, name: []const u8) bool {
    if (entry.len < name.len + 1) return false;
    if (entry[name.len] != '=') return false;
    return string.eql(entry[0..name.len], name);
}

fn valueAfterEq(entry: []const u8) []const u8 {
    var i: usize = 0;
    while (i < entry.len and entry[i] != '=') : (i += 1) {}
    if (i + 1 >= entry.len) return "";
    return entry[i + 1 ..];
}
