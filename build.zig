const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .x86_64,
            .os_tag = .uefi,
        },
    });
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "bootx64",
        .root_module = exe_mod,
    });

    b.default_step.dependOn(&exe.step);

    // b.installArtifact(exe);

    const install_step = b.addInstallArtifact(exe, .{
        .dest_dir = .{
            .override = .{ .custom = "efi/boot" },
        },
    });

    const run_cmd = b.addSystemCommand(&[_][]const u8{
        "qemu-system-x86_64",
        "-bios",
        "/usr/share/ovmf/OVMF.fd",
        "-drive",
        "format=raw,file=fat:rw:zig-out",
        "-serial", "stdio",
        // "-nographic",
    });

    // run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.step.dependOn(&install_step.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
