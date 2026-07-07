//! Freestanding-safe `std` configuration — re-export from each program root:
//! `pub const std_options_debug_io = std_root.std_options_debug_io;` etc.
const std = @import("std");

pub const std_options_debug_io: std.Io = std.Io.failing;

pub const std_options: std.Options = .{
    .page_size_min = 4096,
    .page_size_max = 4096,
};
