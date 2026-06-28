//! Freestanding-safe std configuration for userspace program roots.
const std = @import("std");

pub const std_options_debug_io: std.Io = std.Io.failing;

pub const std_options: std.Options = .{
    .page_size_min = 4096,
    .page_size_max = 4096,
};
