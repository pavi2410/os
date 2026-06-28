const cpu = @import("cpu.zig");
const interrupts = @import("interrupts.zig");
const time_unix = @import("time_unix");

const cmos_addr: u16 = 0x70;
const cmos_data: u16 = 0x71;

const reg_seconds: u8 = 0x00;
const reg_minutes: u8 = 0x02;
const reg_hours: u8 = 0x04;
const reg_status_b: u8 = 0x0B;
const reg_day: u8 = 0x07;
const reg_month: u8 = 0x08;
const reg_year: u8 = 0x09;
const reg_century: u8 = 0x32;

const DateTime = struct {
    year: i32,
    month: i32,
    day: i32,
    hour: i32,
    minute: i32,
    second: i32,
};

var base_unix: i64 = 0;

pub fn init() void {
    const dt = readDateTimeOnce();
    base_unix = time_unix.unixFromCivil(dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second);
}

pub fn realtimeSeconds() i64 {
    const uptime = @divTrunc(interrupts.timerTickCount(), 100);
    return base_unix + @as(i64, @intCast(uptime));
}

fn readDateTimeOnce() DateTime {
    const status_b = cmosRead(reg_status_b);
    const binary = status_b & 0x04 != 0;
    const is_24h = status_b & 0x02 != 0;

    const second = decode(cmosRead(reg_seconds), binary);
    const minute = decode(cmosRead(reg_minutes), binary);
    var hour_raw = cmosRead(reg_hours);
    const pm = !is_24h and hour_raw & 0x80 != 0;
    if (!is_24h) hour_raw &= 0x7F;
    var hour: i32 = decode(hour_raw, binary);
    if (!is_24h) {
        if (hour == 12) hour = 0;
        if (pm) hour += 12;
    }

    const day = decode(cmosRead(reg_day), binary);
    const month = decode(cmosRead(reg_month), binary);
    const year_byte = decode(cmosRead(reg_year), binary);

    var year: i32 = @intCast(year_byte);
    const century_raw = cmosRead(reg_century);
    if (century_raw != 0) {
        const century = decode(century_raw, binary);
        year = @as(i32, century) * 100 + @as(i32, year_byte);
    } else if (year < 70) {
        year += 2000;
    } else {
        year += 1900;
    }

    return .{
        .year = year,
        .month = clamp(@intCast(month), 1, 12),
        .day = clamp(@intCast(day), 1, 31),
        .hour = clamp(hour, 0, 23),
        .minute = clamp(@intCast(minute), 0, 59),
        .second = clamp(@intCast(second), 0, 59),
    };
}

fn clamp(value: i32, lo: i32, hi: i32) i32 {
    if (value < lo) return lo;
    if (value > hi) return hi;
    return value;
}

fn decode(raw: u8, binary: bool) u8 {
    if (binary) return raw;
    const lo = raw & 0x0F;
    const hi = raw >> 4;
    if (lo > 9 or hi > 9) return 0;
    return lo + (hi * 10);
}

fn cmosRead(reg: u8) u8 {
    cpu.outb(cmos_addr, reg);
    return cpu.inb(cmos_data);
}
