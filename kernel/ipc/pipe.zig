pub const ring_size = 4096;

pub const PipeError = error{
    BrokenPipe,
    WouldBlock,
    TooManyPipes,
};

pub const PipeFd = struct {
    handle: u32,
    is_read: bool,
};

const Pipe = struct {
    buf: [ring_size]u8 = undefined,
    read_pos: usize = 0,
    write_pos: usize = 0,
    available: usize = 0,
    ref_count: u8 = 2,
    write_closed: bool = false,
    read_closed: bool = false,
};

const max_pipes = 16;
var pipes: [max_pipes]?Pipe = [_]?Pipe{null} ** max_pipes;

pub fn init() void {
    for (&pipes) |*slot| {
        slot.* = null;
    }
}

pub fn create() PipeError!u32 {
    for (&pipes, 0..) |*slot, i| {
        if (slot.* == null) {
            slot.* = Pipe{};
            return @intCast(i);
        }
    }
    return PipeError.TooManyPipes;
}

pub fn read(handle: u32, buf: []u8) PipeError!usize {
    const pipe = getPipe(handle) orelse return PipeError.BrokenPipe;

    if (pipe.available == 0) {
        if (pipe.write_closed) return 0;
        return error.WouldBlock;
    }

    const to_read = @min(buf.len, pipe.available);
    var total: usize = 0;
    while (total < to_read) {
        const chunk = @min(to_read - total, ring_size - pipe.read_pos);
        @memcpy(buf[total .. total + chunk], pipe.buf[pipe.read_pos .. pipe.read_pos + chunk]);
        total += chunk;
        pipe.read_pos = (pipe.read_pos + chunk) % ring_size;
        pipe.available -= chunk;
    }
    return total;
}

pub fn write(handle: u32, buf: []const u8) PipeError!usize {
    const pipe = getPipe(handle) orelse return PipeError.BrokenPipe;

    if (pipe.read_closed) return PipeError.BrokenPipe;
    if (pipe.write_closed) return PipeError.BrokenPipe;

    if (buf.len == 0) return 0;

    const space = ring_size - pipe.available;
    const to_write = @min(buf.len, space);
    if (to_write == 0) return 0; // buffer full, non-blocking

    var total: usize = 0;
    while (total < to_write) {
        const chunk = @min(to_write - total, ring_size - pipe.write_pos);
        @memcpy(pipe.buf[pipe.write_pos .. pipe.write_pos + chunk], buf[total .. total + chunk]);
        total += chunk;
        pipe.write_pos = (pipe.write_pos + chunk) % ring_size;
        pipe.available += chunk;
    }
    return total;
}

pub fn closeRead(handle: u32) void {
    const pipe = getPipe(handle) orelse return;
    pipe.read_closed = true;
    decRef(handle);
}

pub fn closeWrite(handle: u32) void {
    const pipe = getPipe(handle) orelse return;
    pipe.write_closed = true;
    decRef(handle);
}

fn decRef(handle: u32) void {
    const pipe = getPipe(handle) orelse return;
    if (pipe.ref_count == 0) return;
    pipe.ref_count -= 1;
    if (pipe.ref_count == 0) {
        pipes[handle] = null;
    }
}

fn getPipe(handle: u32) ?*Pipe {
    if (handle >= max_pipes) return null;
    return &(pipes[handle] orelse return null);
}

pub fn dupRef(handle: u32) void {
    const pipe = getPipe(handle) orelse return;
    pipe.ref_count += 1;
}
