pub fn getValue(_: []const u8) ?[]const u8 {
    return null;
}

pub fn init() void {}

pub fn setPair(_: []const u8, _: []const u8) bool {
    return false;
}

pub const max_entries = 16;
pub const entry_max = 128;

pub fn countEntries() usize {
    return 0;
}

pub fn entryAt(_: usize) []const u8 {
    return "";
}

pub fn fillExecEnvp(_: anytype) void {}

pub fn fillExecEnvpWithOverrides(_: anytype, _: anytype) bool {
    return true;
}
