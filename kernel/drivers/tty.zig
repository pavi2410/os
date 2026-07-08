const serial = @import("../arch/x86_64/serial.zig");

pub const TtyError = error{
    WouldBlock,
};

/// Serial console TTY with canonical line editing.
pub const Tty = struct {
    canonical: bool = true,
    echo: bool = true,
    line_buf: [256]u8 = undefined,
    line_len: usize = 0,
    line_ready: bool = false,
    parse_state: AnsiState = .ground,

    pub fn init() Tty {
        return .{};
    }

    pub fn write(self: *Tty, buf: []const u8) usize {
        for (buf) |ch| self.writeOut(ch);
        return buf.len;
    }

    /// Read up to `buf.len` bytes. In canonical mode returns one line at a time.
    pub fn read(self: *Tty, buf: []u8) TtyError!usize {
        if (buf.len == 0) return 0;

        if (!self.canonical) {
            buf[0] = serial.readByteBlocking();
            return 1;
        }

        while (!self.line_ready) {
            const ch = serial.readByteBlocking();
            try self.handleInput(ch);
        }
        self.line_ready = false;

        const copy_len = @min(buf.len, self.line_len);
        @memcpy(buf[0..copy_len], self.line_buf[0..copy_len]);
        self.consumeLine(copy_len);
        return copy_len;
    }

    fn writeOut(self: *Tty, ch: u8) void {
        _ = self;
        serial.writeByte(ch);
    }

    fn echoByte(self: *Tty, ch: u8) void {
        if (!self.echo) return;
        self.writeOut(ch);
    }

    fn consumeLine(self: *Tty, count: usize) void {
        if (count >= self.line_len) {
            self.line_len = 0;
            return;
        }
        const remain = self.line_len - count;
        @memcpy(self.line_buf[0..remain], self.line_buf[count..][0..remain]);
        self.line_len = remain;
    }

    fn finishLine(self: *Tty) TtyError!void {
        if (self.echo) self.writeOut('\n');
        try self.pushLine('\n');
        self.line_ready = true;
    }

    fn handleInput(self: *Tty, ch: u8) TtyError!void {
        switch (self.parse_state) {
            .ground => try self.handleGround(ch),
            .escape => self.parse_state = if (ch == '[') .csi else .ground,
            .csi => {
                self.parse_state = .ground;
                try self.handleCsi(ch);
            },
        }
    }

    fn handleGround(self: *Tty, ch: u8) TtyError!void {
        switch (ch) {
            0x03 => {
                if (self.echo) serial.println("^C", .{});
                self.line_len = 0;
                self.line_ready = false;
                return TtyError.WouldBlock;
            },
            '\r', '\n' => {
                if (!self.line_ready) try self.finishLine();
            },
            0x7F, '\x08' => try self.backspace(),
            else => {
                self.echoByte(ch);
                try self.pushLine(ch);
            },
        }
    }

    fn handleCsi(self: *Tty, ch: u8) TtyError!void {
        switch (ch) {
            'A' => try self.backspace(),
            'C' => if (self.echo) self.echoByte(' '),
            else => {},
        }
    }

    fn backspace(self: *Tty) TtyError!void {
        if (self.line_len == 0) return;
        self.line_len -= 1;
        if (self.echo) serial.writeAll("\x08 \x08");
    }

    fn pushLine(self: *Tty, ch: u8) TtyError!void {
        if (self.line_len >= self.line_buf.len) return TtyError.WouldBlock;
        self.line_buf[self.line_len] = ch;
        self.line_len += 1;
    }
};

const AnsiState = enum {
    ground,
    escape,
    csi,
};

var default_tty: Tty = .{};

pub fn get() *Tty {
    return &default_tty;
}

pub fn init() void {
    default_tty = Tty.init();
}
