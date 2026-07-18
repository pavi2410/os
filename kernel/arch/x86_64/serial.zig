const std = @import("std");
const cpu = @import("cpu.zig");
const spinlock = @import("../../sync/spinlock.zig");

/// COM1 serial port base address
const COM1: u16 = 0x3F8;

/// Serial port registers (offsets from base)
const DATA: u16 = 0; // Data register (read/write)
const INT_ENABLE: u16 = 1; // Interrupt enable register
const FIFO_CTRL: u16 = 2; // FIFO control register
const LINE_CTRL: u16 = 3; // Line control register
const MODEM_CTRL: u16 = 4; // Modem control register
const LINE_STATUS: u16 = 5; // Line status register

var serial_lock: spinlock.SpinLock = .{};

/// Unbuffered so `print` and raw `writeByte` stay ordered on the UART.
var serial_writer: std.Io.Writer = .{
    .vtable = &.{
        .drain = drain,
    },
    .buffer = &.{},
};

/// Initialize the serial port (COM1)
pub fn init() void {
    // Disable all interrupts
    outb(COM1 + INT_ENABLE, 0x00);

    // Enable DLAB (set baud rate divisor)
    outb(COM1 + LINE_CTRL, 0x80);

    // Set divisor to 3 (lo byte) 38400 baud
    outb(COM1 + DATA, 0x03);
    outb(COM1 + INT_ENABLE, 0x00); // (hi byte)

    // 8 bits, no parity, one stop bit
    outb(COM1 + LINE_CTRL, 0x03);

    // Enable FIFO, clear them, with 14-byte threshold
    outb(COM1 + FIFO_CTRL, 0xC7);

    // IRQs enabled, RTS/DSR set
    outb(COM1 + MODEM_CTRL, 0x0B);

    // Set in loopback mode, test the serial chip
    outb(COM1 + MODEM_CTRL, 0x1E);

    // Test serial chip (send byte 0xAE and check if serial returns same byte)
    outb(COM1 + DATA, 0xAE);

    // Check if serial is faulty (i.e: not same byte as sent)
    if (inb(COM1 + DATA) != 0xAE) {
        // Faulty serial port - we can't do much here
        return;
    }

    // If serial is not faulty set it in normal operation mode
    // (not-loopback with IRQs enabled and OUT#1 and OUT#2 bits enabled)
    outb(COM1 + MODEM_CTRL, 0x0F);
}

/// Check if transmit buffer is empty
fn isTransmitEmpty() bool {
    return (inb(COM1 + LINE_STATUS) & 0x20) != 0;
}

/// Write a single byte to the UART with no newline translation.
pub fn writeByteRaw(byte: u8) void {
    while (!isTransmitEmpty()) {}
    outb(COM1 + DATA, byte);
}

/// Write a single byte, mapping `\n` to `\r\n` for serial terminals.
pub fn writeByte(byte: u8) void {
    if (byte == '\n') writeByteRaw('\r');
    writeByteRaw(byte);
}

/// Check if receive buffer has data
pub fn dataReady() bool {
    return (inb(COM1 + LINE_STATUS) & 0x01) != 0;
}

/// Read a byte when available.
pub fn readByte() ?u8 {
    if (!dataReady()) return null;
    return inb(COM1 + DATA);
}

/// Block until a byte is available, then return it.
pub fn readByteBlocking() u8 {
    while (!dataReady()) {
        cpu.sti();
        cpu.hlt();
        cpu.cli();
    }
    return inb(COM1 + DATA);
}

/// Serial console writer (`\n` → `\r\n` on drain).
pub fn writer() *std.Io.Writer {
    return &serial_writer;
}

/// Formatted print via `std.Io.Writer.print`.
pub fn print(comptime fmt: []const u8, args: anytype) void {
    serial_lock.lock();
    defer serial_lock.unlock();
    writer().print(fmt, args) catch {};
}

/// Formatted print with a trailing newline.
pub fn println(comptime fmt: []const u8, args: anytype) void {
    serial_lock.lock();
    defer serial_lock.unlock();
    writer().print(fmt ++ "\n", args) catch {};
}

/// Write bytes through the console writer (applies `\n` → `\r\n`).
pub fn writeAll(bytes: []const u8) void {
    serial_lock.lock();
    defer serial_lock.unlock();
    writer().writeAll(bytes) catch {};
}

fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
    _ = w;
    var consumed: usize = 0;
    if (data.len == 0) return 0;

    for (data[0 .. data.len - 1]) |chunk| {
        for (chunk) |byte| writeByte(byte);
        consumed += chunk.len;
    }

    const pattern = data[data.len - 1];
    var i: usize = 0;
    while (i < splat) : (i += 1) {
        for (pattern) |byte| writeByte(byte);
        consumed += pattern.len;
    }
    return consumed;
}

/// Output a byte to a port
inline fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        : [value] "{al}" (value),
          [port] "{dx}" (port),
    );
}

/// Input a byte from a port
inline fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]"
        : [result] "={al}" (-> u8),
        : [port] "{dx}" (port),
    );
}
