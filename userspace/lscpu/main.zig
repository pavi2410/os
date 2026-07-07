const freestanding_std = @import("freestanding_std");
const libc = @import("libc");

pub const std_options_debug_io = freestanding_std.std_options_debug_io;
pub const std_options = freestanding_std.std_options;

comptime {
    if (@offsetOf(libc.hw.CpuInfo, "vendor") != 0) @compileError("CpuInfo.vendor must be at offset 0");
}

export fn main(_argc: usize, _argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) void {
    _ = _argc;
    _ = _argv;

    var info: libc.hw.CpuInfo = undefined;
    if (libc.hw.getcpuinfo(&info) < 0) {
        writeStr("lscpu: getcpuinfo failed\n");
        libc.process.exit(1);
    }

    writeStr("Architecture:        x86_64\n");
    writeStr("Vendor ID:           ");
    writeStr(libc.hw.zstr(info.vendor[0..]));
    writeStr("\n");
    writeStr("CPU family:          ");
    libc.io.writeU8(info.family);
    writeStr("\nModel:               ");
    libc.io.writeU8(info.model);
    writeStr("\nStepping:            ");
    libc.io.writeU8(info.stepping);
    writeStr("\nModel name:          ");
    writeStr(libc.hw.zstr(info.brand[0..]));
    writeStr("\nAPIC ID:             ");
    libc.io.writeU8(info.apic_id);
    writeStr("\nCPU(s):              ");
    libc.io.writeU32(info.logical_cpus);
    writeStr("\nIOAPIC count:        ");
    libc.io.writeU32(info.ioapic_count);
    writeStr("\n");

    libc.process.exit(0);
}

fn writeStr(s: []const u8) void {
    libc.io.writeStr(s);
}
