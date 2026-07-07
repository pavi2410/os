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
        ulib.io.writeStr("lscpu: getcpuinfo failed\n");
        ulib.process.exit(1);
    }

    ulib.io.writeStr("Architecture:        x86_64\n");
    ulib.io.writeStr("Vendor ID:           ");
    ulib.io.writeStr(ulib.hw.zstr(info.vendor[0..]));
    ulib.io.writeStr("\n");
    ulib.io.writeStr("CPU family:          ");
    ulib.io.writeU8(info.family);
    ulib.io.writeStr("\nModel:               ");
    ulib.io.writeU8(info.model);
    ulib.io.writeStr("\nStepping:            ");
    ulib.io.writeU8(info.stepping);
    ulib.io.writeStr("\nModel name:          ");
    ulib.io.writeStr(ulib.hw.zstr(info.brand[0..]));
    ulib.io.writeStr("\nAPIC ID:             ");
    ulib.io.writeU8(info.apic_id);
    ulib.io.writeStr("\nCPU(s):              ");
    ulib.io.writeU32(info.logical_cpus);
    ulib.io.writeStr("\nIOAPIC count:        ");
    ulib.io.writeU32(info.ioapic_count);
    ulib.io.writeStr("\n");

    ulib.process.exit(0);
}
