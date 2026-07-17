const filesystem = @import("filesystem.zig");
const std = @import("std");

pub const max_mounts = 8;
pub const max_path_len = 64;

pub const MountError = error{
    TooManyMounts,
    InvalidPath,
    NotFound,
};

pub const MountEntry = struct {
    path_buf: [max_path_len]u8 = undefined,
    path_len: u8 = 0,
    ops: ?*const filesystem.Ops = null,

    pub fn path(self: *const MountEntry) []const u8 {
        return self.path_buf[0..self.path_len];
    }
};

pub const Resolved = struct {
    ops: *const filesystem.Ops,
    /// Path relative to the mount root; always absolute (starts with `/`).
    rel_path: []const u8,
    mount_path: []const u8,
};

pub const Table = struct {
    entries: [max_mounts]MountEntry = @splat(.{}),

    pub fn add(self: *Table, mount_path: []const u8, ops: *const filesystem.Ops) MountError!void {
        if (!isAbsoluteMountPath(mount_path)) return MountError.InvalidPath;
        if (mount_path.len > max_path_len) return MountError.InvalidPath;

        for (&self.entries) |*e| {
            if (e.ops != null and std.mem.eql(u8, e.path(), mount_path)) {
                e.ops = ops;
                return;
            }
        }
        for (&self.entries) |*e| {
            if (e.ops == null) {
                @memcpy(e.path_buf[0..mount_path.len], mount_path);
                e.path_len = @intCast(mount_path.len);
                e.ops = ops;
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
            if (e.ops == null) continue;
            if (!prefixMatches(e.path(), path)) continue;
            if (e.path_len > best_len) {
                best_len = e.path_len;
                best_i = i;
            }
        }
        const i = best_i orelse return MountError.NotFound;
        const e = self.entries[i];
        return .{
            .ops = e.ops.?,
            .rel_path = relativePath(e.path(), path),
            .mount_path = e.path(),
        };
    }

    pub fn remove(self: *Table, mount_path: []const u8) MountError!void {
        if (!isAbsoluteMountPath(mount_path)) return MountError.InvalidPath;
        // Never remove the filesystem root.
        if (mount_path.len == 1 and mount_path[0] == '/') return MountError.InvalidPath;
        for (&self.entries) |*e| {
            if (e.ops != null and std.mem.eql(u8, e.path(), mount_path)) {
                e.* = .{};
                return;
            }
        }
        return MountError.NotFound;
    }

    pub fn findExact(self: *const Table, mount_path: []const u8) ?*const MountEntry {
        for (&self.entries) |*e| {
            if (e.ops != null and std.mem.eql(u8, e.path(), mount_path)) return e;
        }
        return null;
    }

    pub fn findOps(self: *const Table, ops: *const filesystem.Ops) ?*const MountEntry {
        for (&self.entries) |*e| {
            if (e.ops == ops) return e;
        }
        return null;
    }

    /// Basename of a non-root mount path (`/tmp` → `tmp`), or null for `/`.
    pub fn mountBasename(path: []const u8) ?[]const u8 {
        if (path.len <= 1) return null;
        if (path[0] != '/') return null;
        return path[1..];
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
