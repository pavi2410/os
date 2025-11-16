const std = @import("std");

/// COM1 serial port base address
const COM1: u16 = 0x3F8;

/// Serial port registers (offsets from base)
const DATA: u16 = 0; // Data register (read/write)
const INT_ENABLE: u16 = 1; // Interrupt enable register
const FIFO_CTRL: u16 = 2; // FIFO control register
const LINE_CTRL: u16 = 3; // Line control register
const MODEM_CTRL: u16 = 4; // Modem control register
const LINE_STATUS: u16 = 5; // Line status register

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

/// Write a single byte to the serial port
pub fn writeByte(byte: u8) void {
    // Wait for transmit buffer to be empty
    while (!isTransmitEmpty()) {}

    outb(COM1 + DATA, byte);
}

/// Write a string to the serial port
pub fn writeString(str: []const u8) void {
    for (str) |c| {
        writeByte(c);
    }
}

/// Write a null-terminated string to the serial port
pub fn writeStringZ(str: [*:0]const u8) void {
    var i: usize = 0;
    while (str[i] != 0) : (i += 1) {
        writeByte(str[i]);
    }
}

/// Printf-style function for serial output
pub fn printf(comptime format: []const u8, args: anytype) void {
    var buffer: [1024]u8 = undefined;
    const result = std.fmt.bufPrint(&buffer, format, args) catch return;
    writeString(result);
}

/// Output a byte to a port
inline fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        : [value] "{al}" (value),
          [port] "N{dx}" (port),
    );
}

/// Input a byte from a port
inline fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]"
        : [result] "={al}" (-> u8),
        : [port] "N{dx}" (port),
    );
}
