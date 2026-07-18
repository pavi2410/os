//! Minimal environ stand-in for host expand tests (stores KEY=value pairs).

pub const max_entries = 16;
pub const entry_max = 128;

var entries: [max_entries][entry_max]u8 = undefined;
var entry_lens: [max_entries]usize = .{0} ** max_entries;
var count: usize = 0;

pub fn init() void {
    count = 0;
}

pub fn getValue(name: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const entry = entries[i][0..entry_lens[i]];
        if (entry.len <= name.len) continue;
        if (entry[name.len] != '=') continue;
        if (!eql(entry[0..name.len], name)) continue;
        return entry[name.len + 1 ..];
    }
    return null;
}

pub fn setPair(key: []const u8, value: []const u8) bool {
    if (key.len == 0 or key.len + 1 + value.len >= entry_max) return false;
    if (count >= max_entries) return false;
    @memcpy(entries[count][0..key.len], key);
    entries[count][key.len] = '=';
    @memcpy(entries[count][key.len + 1 ..][0..value.len], value);
    entry_lens[count] = key.len + 1 + value.len;
    count += 1;
    return true;
}

pub fn countEntries() usize {
    return count;
}

pub fn entryAt(index: usize) []const u8 {
    return entries[index][0..entry_lens[index]];
}

pub fn fillExecEnvp(_: anytype) void {}

pub fn fillExecEnvpWithOverrides(_: anytype, _: anytype) bool {
    return true;
}

fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (x != y) return false;
    }
    return true;
}
