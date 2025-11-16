const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    // Shared boot_info module
    const boot_info_mod = b.createModule(.{
        .root_source_file = b.path("src/boot_info.zig"),
    });

    // Bootloader target (UEFI)
    const boot_target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .x86_64,
            .os_tag = .uefi,
        },
    });

    const boot_mod = b.createModule(.{
        .root_source_file = b.path("src/boot/main.zig"),
        .target = boot_target,
        .optimize = optimize,
    });
    boot_mod.addImport("boot_info", boot_info_mod);

    const bootloader = b.addExecutable(.{
        .name = "bootx64",
        .root_module = boot_mod,
    });

    b.default_step.dependOn(&bootloader.step);

    // Install bootloader to efi/boot/
    const install_boot = b.addInstallArtifact(bootloader, .{
        .dest_dir = .{
            .override = .{ .custom = "efi/boot" },
        },
    });

    // Kernel target (freestanding x86_64)
    const kernel_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    });

    const kernel_mod = b.createModule(.{
        .root_source_file = b.path("src/kernel/main.zig"),
        .target = kernel_target,
        .optimize = optimize,
        .code_model = .kernel,
    });
    kernel_mod.addImport("boot_info", boot_info_mod);

    const kernel = b.addExecutable(.{
        .name = "kernel.elf",
        .root_module = kernel_mod,
    });

    // Set kernel to output ELF format
    kernel.link_function_sections = true;
    kernel.setLinkerScript(b.path("linker.ld"));

    // Set the image base to 1MB - this is critical for position-dependent code
    kernel.image_base = 0x100000;

    b.default_step.dependOn(&kernel.step);

    // Install kernel to root of zig-out/
    const install_kernel = b.addInstallArtifact(kernel, .{
        .dest_dir = .{
            .override = .{ .custom = "" },
        },
    });

    // Make sure both are installed
    b.getInstallStep().dependOn(&install_boot.step);
    b.getInstallStep().dependOn(&install_kernel.step);

    // QEMU run command
    const run_cmd = b.addSystemCommand(&[_][]const u8{
        "qemu-system-x86_64",
        // "-bios",
        // "/usr/share/ovmf/OVMF.fd",
        "-drive",
        "if=pflash,format=raw,readonly=on,file=./ovmf/OVMF_CODE_4M.fd",
        "-drive",
        "if=pflash,format=raw,file=./ovmf/OVMF_VARS_4M.fd",
        "-drive",
        "format=raw,file=fat:rw:zig-out",
        "-serial",
        "stdio",
        // "-nographic",
    });

    run_cmd.step.dependOn(&install_boot.step);
    run_cmd.step.dependOn(&install_kernel.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the OS");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const boot_tests = b.addTest(.{
        .root_module = boot_mod,
    });

    const kernel_tests = b.addTest(.{
        .root_module = kernel_mod,
    });

    const run_boot_tests = b.addRunArtifact(boot_tests);
    const run_kernel_tests = b.addRunArtifact(kernel_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_boot_tests.step);
    test_step.dependOn(&run_kernel_tests.step);
}
