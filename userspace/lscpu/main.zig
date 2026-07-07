const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;

const ulib = @import("ulib");

comptime {
    if (@offsetOf(ulib.hw.CpuInfo, "vendor") != 0) @compileError("CpuInfo.vendor must be at offset 0");
}

export fn main(_argc: usize, _argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) void {
    _ = _argc;
    _ = _argv;

    var info: ulib.hw.CpuInfo = undefined;
    if (ulib.hw.getcpuinfo(&info) < 0) {
        writeStr("lscpu: getcpuinfo failed\n");
        ulib.process.exit(1);
    }

    writeStr("Architecture:        x86_64\n");
    writeStr("Vendor ID:           ");
    writeStr(ulib.hw.zstr(info.vendor[0..]));
    writeStr("\n");
    writeStr("CPU family:          ");
    ulib.io.writeU8(info.family);
    writeStr("\nModel:               ");
    ulib.io.writeU8(info.model);
    writeStr("\nStepping:            ");
    ulib.io.writeU8(info.stepping);
    writeStr("\nModel name:          ");
    writeStr(ulib.hw.zstr(info.brand[0..]));
    writeStr("\nAPIC ID:             ");
    ulib.io.writeU8(info.apic_id);
    writeStr("\nCPU(s):              ");
    ulib.io.writeU32(info.logical_cpus);
    writeStr("\nIOAPIC count:        ");
    ulib.io.writeU32(info.ioapic_count);
    writeStr("\n");

    ulib.process.exit(0);
}

fn writeStr(s: []const u8) void {
    ulib.io.writeStr(s);
}
