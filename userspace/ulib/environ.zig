const string = @import("string.zig");

pub fn getenv(name: []const u8, argc: usize, argv: [*]const [*]u8) ?[]const u8 {
    var i: usize = 0;
    while (true) {
        const ptr = argv[argc + 1 + i];
        if (@intFromPtr(ptr) == 0) break;
        const entry = cStrSlice(@ptrCast(ptr));
        if (entryMatchesName(entry, name)) {
            return valueAfterEq(entry);
        }
        i += 1;
    }
    return null;
}

fn cStrSlice(ptr: [*:0]const u8) []const u8 {
    var len: usize = 0;
    while (ptr[len] != 0) : (len += 1) {}
    return ptr[0..len];
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
