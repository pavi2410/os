pub const Fault = error{Fault};

pub fn cString(ptr: u64, max_len: usize) ?[]const u8 {
    if (ptr == 0) return null;
    const start: [*]const u8 = @ptrFromInt(ptr);
    var len: usize = 0;
    while (len < max_len) : (len += 1) {
        if (start[len] == 0) return start[0..len];
    }
    return null;
}

pub fn value(comptime T: type, ptr: u64) ?T {
    if (ptr == 0) return null;
    return @as(*const T, @ptrFromInt(ptr)).*;
}

pub fn outPtr(comptime T: type, ptr: u64) ?*T {
    if (ptr == 0) return null;
    return @ptrFromInt(ptr);
}

pub fn bytes(ptr: u64, len: usize) ?[]u8 {
    if (ptr == 0) return null;
    const raw: [*]u8 = @ptrFromInt(ptr);
    return raw[0..len];
}

pub fn constBytes(ptr: u64, len: usize) ?[]const u8 {
    if (ptr == 0) return null;
    const raw: [*]const u8 = @ptrFromInt(ptr);
    return raw[0..len];
}

pub fn slice(comptime T: type, ptr: u64, len: usize) ?[]T {
    if (ptr == 0) return null;
    const raw: [*]T = @ptrFromInt(ptr);
    return raw[0..len];
}

pub fn readArgv(argv_ptr: u64, out: [][]const u8, max_cstring_len: usize) Fault!usize {
    if (argv_ptr == 0) return 0;
    var count: usize = 0;
    var idx: usize = 0;
    while (idx < out.len) : (idx += 1) {
        const slot_ptr: *const u64 = @ptrFromInt(argv_ptr + idx * @sizeOf(u64));
        const arg_ptr = slot_ptr.*;
        if (arg_ptr == 0) break;
        const arg = cString(arg_ptr, max_cstring_len) orelse return error.Fault;
        out[count] = arg;
        count += 1;
    }
    return count;
}
