const std = @import("std");

pub const ring_size = 4096;

pub const PipeError = error{
    BrokenPipe,
    WouldBlock,
    TooManyPipes,
};

/// Index into a Runtime-owned pipe table. Descriptor translation belongs in
/// the syscall layer; IPC never accepts a process descriptor directly.
pub const Handle = u32;

pub const PipeFd = struct {
    handle: Handle,
    is_read: bool,
};

const Pipe = struct {
    buf: [ring_size]u8 = undefined,
    read_pos: usize = 0,
    write_pos: usize = 0,
    available: usize = 0,
    readers: u8 = 1,
    writers: u8 = 1,
};

pub const max_pipes = 16;

/// Owns pipe storage. Kernel composition will inject this table; the module
/// wrappers below remain only while callers migrate.
pub const PipeTable = struct {
    pipes: [max_pipes]?Pipe = [_]?Pipe{null} ** max_pipes,

    pub fn init(self: *PipeTable) void {
        self.* = .{};
    }

    pub fn create(self: *PipeTable) PipeError!Handle {
        for (&self.pipes, 0..) |*slot, i| {
            if (slot.* == null) {
                slot.* = Pipe{};
                return @intCast(i);
            }
        }
        return PipeError.TooManyPipes;
    }

    pub fn read(self: *PipeTable, handle: Handle, buf: []u8) PipeError!usize {
        const pipe = self.get(handle) orelse return PipeError.BrokenPipe;
        if (pipe.available == 0) return if (pipe.writers == 0) 0 else error.WouldBlock;
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

    pub fn write(self: *PipeTable, handle: Handle, buf: []const u8) PipeError!usize {
        const pipe = self.get(handle) orelse return PipeError.BrokenPipe;
        if (pipe.readers == 0) return PipeError.BrokenPipe;
        const to_write = @min(buf.len, ring_size - pipe.available);
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

    pub fn closeRead(self: *PipeTable, handle: Handle) void { self.close(handle, true); }
    pub fn closeWrite(self: *PipeTable, handle: Handle) void { self.close(handle, false); }

    pub fn dupRef(self: *PipeTable, handle: Handle, is_read: bool) void {
        const pipe = self.get(handle) orelse return;
        if (is_read) {
            if (pipe.readers != std.math.maxInt(u8)) pipe.readers += 1;
        } else if (pipe.writers != std.math.maxInt(u8)) {
            pipe.writers += 1;
        }
    }

    fn close(self: *PipeTable, handle: Handle, is_read: bool) void {
        const pipe = self.get(handle) orelse return;
        if (is_read and pipe.readers > 0) pipe.readers -= 1;
        if (!is_read and pipe.writers > 0) pipe.writers -= 1;
        if (pipe.readers == 0 and pipe.writers == 0) self.pipes[handle] = null;
    }

    fn get(self: *PipeTable, handle: Handle) ?*Pipe {
        if (handle >= max_pipes) return null;
        return &(self.pipes[handle] orelse return null);
    }
};

/// Runtime-owned IPC service. Additional IPC primitives join this owner here.
pub const Ipc = struct {
    pipes: PipeTable = .{},

    pub fn init(self: *Ipc) void { self.pipes.init(); }

    pub fn create(self: *Ipc) PipeError!Handle { return self.pipes.create(); }
    pub fn read(self: *Ipc, handle: Handle, buf: []u8) PipeError!usize { return self.pipes.read(handle, buf); }
    pub fn write(self: *Ipc, handle: Handle, buf: []const u8) PipeError!usize { return self.pipes.write(handle, buf); }
    pub fn closeRead(self: *Ipc, handle: Handle) void { self.pipes.closeRead(handle); }
    pub fn closeWrite(self: *Ipc, handle: Handle) void { self.pipes.closeWrite(handle); }
    pub fn dupRef(self: *Ipc, handle: Handle, is_read: bool) void { self.pipes.dupRef(handle, is_read); }
};
