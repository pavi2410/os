const filesystem = @import("filesystem.zig");
const std = @import("std");

pub const max_mounts = 8;

pub const MountError = error{
    TooManyMounts,
    InvalidPath,
    NotFound,
};

pub const MountEntry = struct {
    path: []const u8 = "",
    ops: ?*const filesystem.Ops = null,
};

pub const Resolved = struct {
    ops: *const filesystem.Ops,
    /// Path relative to the mount root; always absolute (starts with `/`).
    rel_path: []const u8,
    mount_path: []const u8,
};

pub const Table = struct {
    entries: [max_mounts]MountEntry = @splat(.{}),

    pub fn add(self: *Table, path: []const u8, ops: *const filesystem.Ops) MountError!void {
        if (!isAbsoluteMountPath(path)) return MountError.InvalidPath;
        for (&self.entries) |*e| {
            if (e.ops != null and std.mem.eql(u8, e.path, path)) {
                e.ops = ops;
                return;
            }
        }
        for (&self.entries) |*e| {
            if (e.ops == null) {
                e.* = .{ .path = path, .ops = ops };
                return;
            }
        }
        return MountError.TooManyMounts;
    }

    pub fn resolve(self: *const Table, path: []const u8) MountError!Resolved {
        if (path.len == 0 or path[0] != '/') return MountError.InvalidPath;

        var best_i: ?usize = null;
        var best_len: usize = 0;
        for (self.entries, 0..) |e, i| {
            const ops = e.ops orelse continue;
            _ = ops;
            if (!prefixMatches(e.path, path)) continue;
            if (e.path.len > best_len) {
                best_len = e.path.len;
                best_i = i;
            }
        }
        const i = best_i orelse return MountError.NotFound;
        const e = self.entries[i];
        return .{
            .ops = e.ops.?,
            .rel_path = relativePath(e.path, path),
            .mount_path = e.path,
        };
    }

    pub fn remove(self: *Table, path: []const u8) MountError!void {
        if (!isAbsoluteMountPath(path)) return MountError.InvalidPath;
        // Never remove the filesystem root.
        if (path.len == 1 and path[0] == '/') return MountError.InvalidPath;
        for (&self.entries) |*e| {
            if (e.ops != null and std.mem.eql(u8, e.path, path)) {
                e.* = .{};
                return;
            }
        }
        return MountError.NotFound;
    }
};

pub fn isAbsoluteMountPath(path: []const u8) bool {
    if (path.len == 0 or path[0] != '/') return false;
    if (path.len == 1) return true;
    // No trailing slash on non-root mounts.
    if (path[path.len - 1] == '/') return false;
    return true;
}

/// True when `mount_path` is a path-prefix of `path` on a component boundary.
pub fn prefixMatches(mount_path: []const u8, path: []const u8) bool {
    if (mount_path.len == 1 and mount_path[0] == '/') return path.len >= 1 and path[0] == '/';
    if (path.len < mount_path.len) return false;
    if (!std.mem.eql(u8, path[0..mount_path.len], mount_path)) return false;
    return path.len == mount_path.len or path[mount_path.len] == '/';
}

pub fn relativePath(mount_path: []const u8, path: []const u8) []const u8 {
    if (mount_path.len == 1 and mount_path[0] == '/') return path;
    if (path.len == mount_path.len) return "/";
    return path[mount_path.len..];
}
