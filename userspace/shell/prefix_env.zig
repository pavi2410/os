const argv = @import("argv.zig");
const environ = @import("environ.zig");

pub const max_overrides = 8;

var override_bufs: [max_overrides][environ.entry_max]u8 = undefined;
var override_lens: [max_overrides]usize = undefined;
var override_count: usize = 0;

pub fn clear() void {
    override_count = 0;
}

pub fn count() usize {
    return override_count;
}

pub fn overrideAt(index: usize) []const u8 {
    return override_bufs[index][0..override_lens[index]];
}

pub fn isAssignment(word: []const u8) bool {
    const eq = indexOfScalar(word, '=') orelse return false;
    if (eq == 0) return false;
    return isValidName(word[0..eq]);
}

pub fn peel(parsed: *argv.Parsed) bool {
    while (parsed.argc > 0 and isAssignment(parsed.args[0])) {
        if (override_count >= max_overrides) return false;
        const word = parsed.args[0];
        const eq = indexOfScalar(word, '=').?;
        if (!writeOverride(word[0..eq], word[eq + 1 ..])) return false;

        var i: usize = 0;
        while (i + 1 < parsed.argc) : (i += 1) {
            parsed.args[i] = parsed.args[i + 1];
        }
        parsed.argc -= 1;
    }
    return parsed.argc > 0;
}

pub fn lookup(name: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < override_count) : (i += 1) {
        const entry = overrideAt(i);
        if (entryMatchesName(entry, name)) return valueAfterEq(entry);
    }
    return environ.getValue(name);
}

fn writeOverride(key: []const u8, value: []const u8) bool {
    if (key.len + 1 + value.len >= environ.entry_max) return false;
    var pos: usize = 0;
    @memcpy(override_bufs[override_count][0..key.len], key);
    pos = key.len;
    override_bufs[override_count][pos] = '=';
    pos += 1;
    @memcpy(override_bufs[override_count][pos .. pos + value.len], value);
    pos += value.len;
    override_bufs[override_count][pos] = 0;
    override_lens[override_count] = pos;
    override_count += 1;
    return true;
}

fn isValidName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (!isNameStart(name[0])) return false;
    var i: usize = 1;
    while (i < name.len) : (i += 1) {
        if (!isNameChar(name[i])) return false;
    }
    return true;
}

fn isNameStart(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        ch == '_';
}

fn isNameChar(ch: u8) bool {
    return isNameStart(ch) or (ch >= '0' and ch <= '9');
}

fn entryMatchesName(entry: []const u8, name: []const u8) bool {
    if (entry.len < name.len + 1) return false;
    if (entry[name.len] != '=') return false;
    return eql(entry[0..name.len], name);
}

fn indexOfScalar(s: []const u8, ch: u8) ?usize {
    for (s, 0..) |byte, i| {
        if (byte == ch) return i;
    }
    return null;
}

fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        if (left != right) return false;
    }
    return true;
}

fn valueAfterEq(entry: []const u8) []const u8 {
    var i: usize = 0;
    while (i < entry.len and entry[i] != '=') : (i += 1) {}
    if (i + 1 >= entry.len) return "";
    return entry[i + 1 ..];
}
