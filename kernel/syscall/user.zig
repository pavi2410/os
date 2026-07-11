const builtin = @import("builtin");
const std = @import("std");

pub const Fault = error{Fault};

/// Exclusive upper bound of the canonical lower-half user address space.
pub const user_top: u64 = 0x0000_8000_0000_0000;

/// Validate the arithmetic and architectural portion of a user range.
/// Page-table permission checks belong to the caller that has an address space.
pub fn range(ptr: u64, len: usize) bool {
    if (ptr == 0) return false;
    const len_u64: u64 = @intCast(len);
    if (len_u64 > std.math.maxInt(u64) - ptr) return false;
    const end = ptr + len_u64;

    // Host tests use native addresses, which are not guest user virtual
    // addresses. The target path is the security boundary.
    if (builtin.os.tag != .freestanding) return true;
    return ptr < user_top and end <= user_top;
}

pub fn cString(ptr: u64, max_len: usize) ?[]const u8 {
    if (!range(ptr, 1)) return null;
    const start: [*]const u8 = @ptrFromInt(ptr);
    var len: usize = 0;
    while (len < max_len) : (len += 1) {
        if (!range(ptr, len + 1)) return null;
        if (start[len] == 0) return start[0..len];
    }
    return null;
}

pub fn value(comptime T: type, ptr: u64) ?T {
    if (!range(ptr, @sizeOf(T))) return null;
    return @as(*const T, @ptrFromInt(ptr)).*;
}

pub fn outPtr(comptime T: type, ptr: u64) ?*T {
    if (!range(ptr, @sizeOf(T))) return null;
    return @ptrFromInt(ptr);
}

pub fn bytes(ptr: u64, len: usize) ?[]u8 {
    if (!range(ptr, len)) return null;
    const raw: [*]u8 = @ptrFromInt(ptr);
    return raw[0..len];
}

pub fn constBytes(ptr: u64, len: usize) ?[]const u8 {
    if (!range(ptr, len)) return null;
    const raw: [*]const u8 = @ptrFromInt(ptr);
    return raw[0..len];
}

pub fn slice(comptime T: type, ptr: u64, len: usize) ?[]T {
    if (len > std.math.maxInt(usize) / @sizeOf(T)) return null;
    if (!range(ptr, len * @sizeOf(T))) return null;
    const raw: [*]T = @ptrFromInt(ptr);
    return raw[0..len];
}

pub fn readArgv(argv_ptr: u64, out: [][]const u8, max_cstring_len: usize) Fault!usize {
    return readPtrArray(argv_ptr, out, max_cstring_len);
}

pub fn readEnvp(envp_ptr: u64, out: [][]const u8, max_cstring_len: usize) Fault!usize {
    return readPtrArray(envp_ptr, out, max_cstring_len);
}

fn readPtrArray(ptr: u64, out: [][]const u8, max_cstring_len: usize) Fault!usize {
    if (ptr == 0) return 0;
    var count: usize = 0;
    var idx: usize = 0;
    while (idx < out.len) : (idx += 1) {
        const idx_u64: u64 = @intCast(idx);
        if (idx_u64 > std.math.maxInt(u64) / @sizeOf(u64)) return error.Fault;
        const slot_addr = ptr + idx_u64 * @sizeOf(u64);
        if (!range(slot_addr, @sizeOf(u64))) return error.Fault;
        const slot_ptr: *const u64 = @ptrFromInt(slot_addr);
        const entry_ptr = slot_ptr.*;
        if (entry_ptr == 0) break;
        const entry = cString(entry_ptr, max_cstring_len) orelse return error.Fault;
        out[count] = entry;
        count += 1;
    }
    return count;
}
