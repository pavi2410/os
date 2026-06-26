const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    const kernel_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_features_add = std.Target.x86.featureSet(&.{ .popcnt, .soft_float }),
        .cpu_features_sub = std.Target.x86.featureSet(&.{ .avx, .avx2, .sse, .sse2, .mmx }),
    });

    const user_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    });

    const user_optimize: std.builtin.OptimizeMode = .ReleaseSmall;

    const user_libc = b.createModule(.{
        .root_source_file = b.path("userspace/libc.zig"),
        .target = user_target,
        .optimize = user_optimize,
    });

    const hello = b.addExecutable(.{
        .name = "hello",
        .root_module = b.createModule(.{
            .root_source_file = b.path("userspace/hello/main.zig"),
            .target = user_target,
            .optimize = user_optimize,
        }),
    });
    hello.setLinkerScript(b.path("userspace/linker.ld"));
    hello.root_module.addImport("libc", user_libc);

    const shell = b.addExecutable(.{
        .name = "shell",
        .root_module = b.createModule(.{
            .root_source_file = b.path("userspace/shell/main.zig"),
            .target = user_target,
            .optimize = user_optimize,
        }),
    });
    shell.setLinkerScript(b.path("userspace/linker.ld"));
    shell.root_module.addImport("libc", user_libc);

    const install_hello = b.addInstallArtifact(hello, .{});
    const install_shell = b.addInstallArtifact(shell, .{});
    b.getInstallStep().dependOn(&install_hello.step);
    b.getInstallStep().dependOn(&install_shell.step);

    const sync_bins = b.addSystemCommand(&.{
        "sh",
        "-c",
        "mkdir -p kernel/proc/bins && cp zig-out/bin/hello zig-out/bin/shell kernel/proc/bins/",
    });
    sync_bins.step.dependOn(&install_hello.step);
    sync_bins.step.dependOn(&install_shell.step);

    const limine_kernel_mod = b.createModule(.{
        .root_source_file = b.path("kernel/boot/limine.zig"),
        .target = kernel_target,
        .optimize = optimize,
    });

    const kernel_mod = b.createModule(.{
        .root_source_file = b.path("kernel/main.zig"),
        .target = kernel_target,
        .optimize = optimize,
        .code_model = .kernel,
    });
    kernel_mod.addImport("limine", limine_kernel_mod);

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_module = kernel_mod,
    });
    kernel.use_llvm = true;
    kernel.link_function_sections = true;
    kernel.setLinkerScript(b.path("kernel/linker.ld"));
    kernel.step.dependOn(&install_hello.step);
    kernel.step.dependOn(&install_shell.step);
    kernel.step.dependOn(&sync_bins.step);

    const install_kernel = b.addInstallArtifact(kernel, .{});
    b.getInstallStep().dependOn(&install_kernel.step);
    b.default_step.dependOn(&install_kernel.step);

    const kernel_path = b.getInstallPath(.bin, "kernel");
    const iso_path = b.pathJoin(&.{ b.install_path, "os.iso" });
    const disk_path = b.pathJoin(&.{ b.install_path, "disk.img" });

    const create_disk = b.addSystemCommand(&.{
        "sh",
        b.path("scripts/create-disk.sh").getPath(b),
    });

    const build_iso = b.addSystemCommand(&.{
        "sh",
        b.path("scripts/build-iso.sh").getPath(b),
        kernel_path,
        iso_path,
    });
    build_iso.step.dependOn(&install_kernel.step);

    const iso_step = b.step("iso", "Build a bootable Limine ISO");
    iso_step.dependOn(&build_iso.step);

    const run_cmd = b.addSystemCommand(&.{
        "qemu-system-x86_64",
        "-M", "q35",
        "-cdrom", iso_path,
        "-boot", "d",
        "-drive", b.fmt("file={s},if=none,format=raw,id=disk0", .{disk_path}),
        "-device", "virtio-blk-pci,drive=disk0,disable-legacy=on",
        "-serial", "stdio",
    });
    run_cmd.step.dependOn(&build_iso.step);
    run_cmd.step.dependOn(&create_disk.step);

    const run_uefi_cmd = b.addSystemCommand(&.{
        "qemu-system-x86_64",
        "-M", "q35",
        "-drive", "if=pflash,format=raw,readonly=on,file=./ovmf/OVMF_CODE_4M.fd",
        "-drive", "if=pflash,format=raw,file=./ovmf/OVMF_VARS_4M.fd",
        "-cdrom", iso_path,
        "-drive", b.fmt("file={s},if=none,format=raw,id=disk0", .{disk_path}),
        "-device", "virtio-blk-pci,drive=disk0,disable-legacy=on",
        "-serial", "stdio",
    });
    run_uefi_cmd.step.dependOn(&build_iso.step);
    run_uefi_cmd.step.dependOn(&create_disk.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
        run_uefi_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Build the ISO and run in QEMU (SeaBIOS)");
    run_step.dependOn(&run_cmd.step);

    const run_uefi_step = b.step("run-uefi", "Build the ISO and run in QEMU (OVMF/UEFI)");
    run_uefi_step.dependOn(&run_uefi_cmd.step);

    const limine_mod = b.createModule(.{
        .root_source_file = b.path("kernel/boot/limine.zig"),
        .target = b.graph.host,
    });

    const memory_map_host_mod = b.createModule(.{
        .root_source_file = b.path("kernel/mm/memory_map.zig"),
        .target = b.graph.host,
    });
    memory_map_host_mod.addImport("limine", limine_mod);

    const memory_map_test_mod = b.createModule(.{
        .root_source_file = b.path("test/memory_map_test.zig"),
        .target = b.graph.host,
    });
    memory_map_test_mod.addImport("memory_map", memory_map_host_mod);
    memory_map_test_mod.addImport("limine", limine_mod);

    const memory_map_tests = b.addTest(.{
        .root_module = memory_map_test_mod,
    });

    const run_memory_map_tests = b.addRunArtifact(memory_map_tests);

    const physical_bitmap_host_mod = b.createModule(.{
        .root_source_file = b.path("kernel/mm/physical_bitmap.zig"),
        .target = b.graph.host,
    });

    const physical_test_mod = b.createModule(.{
        .root_source_file = b.path("test/physical_test.zig"),
        .target = b.graph.host,
    });
    physical_test_mod.addImport("physical_bitmap", physical_bitmap_host_mod);

    const physical_tests = b.addTest(.{
        .root_module = physical_test_mod,
    });

    const run_physical_tests = b.addRunArtifact(physical_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_memory_map_tests.step);
    test_step.dependOn(&run_physical_tests.step);
}
