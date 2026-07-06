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

    const abi_syscall_user = b.createModule(.{
        .root_source_file = b.path("common/abi/syscall.zig"),
        .target = user_target,
        .optimize = user_optimize,
    });
    const abi_fs_user = b.createModule(.{
        .root_source_file = b.path("common/abi/fs.zig"),
        .target = user_target,
        .optimize = user_optimize,
    });
    const abi_net_user = b.createModule(.{
        .root_source_file = b.path("common/abi/net.zig"),
        .target = user_target,
        .optimize = user_optimize,
    });

    const user_libc = b.createModule(.{
        .root_source_file = b.path("userspace/libc/mod.zig"),
        .target = user_target,
        .optimize = user_optimize,
    });
    user_libc.addImport("abi_syscall", abi_syscall_user);
    user_libc.addImport("abi_fs", abi_fs_user);
    user_libc.addImport("abi_net", abi_net_user);

    const dns_codec_user = b.createModule(.{
        .root_source_file = b.path("userspace/net/dns_codec.zig"),
        .target = user_target,
        .optimize = user_optimize,
    });
    user_libc.addImport("dns_codec", dns_codec_user);

    const freestanding_std = b.createModule(.{
        .root_source_file = b.path("userspace/freestanding_std.zig"),
        .target = user_target,
        .optimize = user_optimize,
    });

    const time_unix_user = b.createModule(.{
        .root_source_file = b.path("common/time_unix.zig"),
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
    hello.root_module.addImport("freestanding_std", freestanding_std);

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
    shell.root_module.addImport("freestanding_std", freestanding_std);
    shell.root_module.addImport("time_unix", time_unix_user);

    const user_bin_dir: std.Build.InstallDir = .{ .custom = "userspace/bin" };
    const user_install = std.Build.Step.InstallArtifact.Options{
        .dest_dir = .{ .override = user_bin_dir },
    };

    const install_hello = b.addInstallArtifact(hello, user_install);
    const install_shell = b.addInstallArtifact(shell, user_install);

    const dig = b.addExecutable(.{
        .name = "dig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("userspace/dig/main.zig"),
            .target = user_target,
            .optimize = user_optimize,
        }),
    });
    dig.setLinkerScript(b.path("userspace/linker.ld"));
    dig.root_module.addImport("libc", user_libc);
    dig.root_module.addImport("freestanding_std", freestanding_std);
    const install_dig = b.addInstallArtifact(dig, user_install);

    const ping = b.addExecutable(.{
        .name = "ping",
        .root_module = b.createModule(.{
            .root_source_file = b.path("userspace/ping/main.zig"),
            .target = user_target,
            .optimize = user_optimize,
        }),
    });
    ping.setLinkerScript(b.path("userspace/linker.ld"));
    ping.root_module.addImport("libc", user_libc);
    ping.root_module.addImport("freestanding_std", freestanding_std);
    const install_ping = b.addInstallArtifact(ping, user_install);

    const curl = b.addExecutable(.{
        .name = "curl",
        .root_module = b.createModule(.{
            .root_source_file = b.path("userspace/curl/main.zig"),
            .target = user_target,
            .optimize = user_optimize,
        }),
    });
    curl.setLinkerScript(b.path("userspace/linker.ld"));
    curl.root_module.addImport("libc", user_libc);
    curl.root_module.addImport("freestanding_std", freestanding_std);
    curl.root_module.addImport("target.zig", b.createModule(.{
        .root_source_file = b.path("userspace/curl/target.zig"),
        .target = user_target,
        .optimize = user_optimize,
    }));
    const install_curl = b.addInstallArtifact(curl, user_install);

    const ip = b.addExecutable(.{
        .name = "ip",
        .root_module = b.createModule(.{
            .root_source_file = b.path("userspace/ip/main.zig"),
            .target = user_target,
            .optimize = user_optimize,
        }),
    });
    ip.setLinkerScript(b.path("userspace/linker.ld"));
    ip.root_module.addImport("libc", user_libc);
    ip.root_module.addImport("freestanding_std", freestanding_std);
    const install_ip = b.addInstallArtifact(ip, user_install);

    b.getInstallStep().dependOn(&install_hello.step);
    b.getInstallStep().dependOn(&install_shell.step);
    b.getInstallStep().dependOn(&install_dig.step);
    b.getInstallStep().dependOn(&install_ping.step);
    b.getInstallStep().dependOn(&install_curl.step);
    b.getInstallStep().dependOn(&install_ip.step);

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
    const abi_syscall_kernel = b.createModule(.{
        .root_source_file = b.path("common/abi/syscall.zig"),
        .target = kernel_target,
        .optimize = optimize,
    });
    const abi_fs_kernel = b.createModule(.{
        .root_source_file = b.path("common/abi/fs.zig"),
        .target = kernel_target,
        .optimize = optimize,
    });
    const abi_net_kernel = b.createModule(.{
        .root_source_file = b.path("common/abi/net.zig"),
        .target = kernel_target,
        .optimize = optimize,
    });
    kernel_mod.addImport("abi_syscall", abi_syscall_kernel);
    kernel_mod.addImport("abi_fs", abi_fs_kernel);
    kernel_mod.addImport("abi_net", abi_net_kernel);

    const time_unix_kernel = b.createModule(.{
        .root_source_file = b.path("common/time_unix.zig"),
        .target = kernel_target,
        .optimize = optimize,
    });
    kernel_mod.addImport("time_unix", time_unix_kernel);

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_module = kernel_mod,
    });
    kernel.use_llvm = true;
    kernel.link_function_sections = true;
    kernel.setLinkerScript(b.path("kernel/linker.ld"));

    const install_kernel = b.addInstallArtifact(kernel, .{});
    b.getInstallStep().dependOn(&install_kernel.step);
    b.default_step.dependOn(&install_kernel.step);

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
        .root_source_file = b.path("test/kernel/memory_map_test.zig"),
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
        .root_source_file = b.path("test/kernel/physical_test.zig"),
        .target = b.graph.host,
    });
    physical_test_mod.addImport("physical_bitmap", physical_bitmap_host_mod);

    const physical_tests = b.addTest(.{
        .root_module = physical_test_mod,
    });

    const run_physical_tests = b.addRunArtifact(physical_tests);

    const block_host_mod = b.createModule(.{
        .root_source_file = b.path("kernel/drivers/block.zig"),
        .target = b.graph.host,
    });
    const net_device_host_mod = b.createModule(.{
        .root_source_file = b.path("kernel/drivers/net_device.zig"),
        .target = b.graph.host,
    });

    const device_registry_test_mod = b.createModule(.{
        .root_source_file = b.path("test/kernel/device_registry_test.zig"),
        .target = b.graph.host,
    });
    device_registry_test_mod.addImport("block", block_host_mod);
    device_registry_test_mod.addImport("net_device", net_device_host_mod);

    const device_registry_tests = b.addTest(.{
        .root_module = device_registry_test_mod,
    });
    const run_device_registry_tests = b.addRunArtifact(device_registry_tests);

    const icmp_test_mod = b.createModule(.{
        .root_source_file = b.path("kernel/net/icmp_test.zig"),
        .target = b.graph.host,
    });

    const icmp_tests = b.addTest(.{
        .root_module = icmp_test_mod,
    });
    const run_icmp_tests = b.addRunArtifact(icmp_tests);

    const tcp_test_mod = b.createModule(.{
        .root_source_file = b.path("kernel/net/tcp_test.zig"),
        .target = b.graph.host,
    });

    const tcp_tests = b.addTest(.{
        .root_module = tcp_test_mod,
    });
    const run_tcp_tests = b.addRunArtifact(tcp_tests);

    const curl_target_mod = b.createModule(.{
        .root_source_file = b.path("userspace/curl/target.zig"),
        .target = b.graph.host,
    });

    const curl_target_test_mod = b.createModule(.{
        .root_source_file = b.path("test/userspace/curl_target_test.zig"),
        .target = b.graph.host,
    });
    curl_target_test_mod.addImport("curl_target", curl_target_mod);

    const curl_target_tests = b.addTest(.{
        .root_module = curl_target_test_mod,
    });
    const run_curl_target_tests = b.addRunArtifact(curl_target_tests);

    const dns_codec_mod = b.createModule(.{
        .root_source_file = b.path("userspace/net/dns_codec.zig"),
        .target = b.graph.host,
    });

    const dns_codec_test_mod = b.createModule(.{
        .root_source_file = b.path("test/userspace/dns_codec_test.zig"),
        .target = b.graph.host,
    });
    dns_codec_test_mod.addImport("dns_codec", dns_codec_mod);

    const dns_codec_tests = b.addTest(.{
        .root_module = dns_codec_test_mod,
    });
    const run_dns_codec_tests = b.addRunArtifact(dns_codec_tests);

    const abi_syscall_host = b.createModule(.{
        .root_source_file = b.path("common/abi/syscall.zig"),
        .target = b.graph.host,
    });
    const abi_fs_host = b.createModule(.{
        .root_source_file = b.path("common/abi/fs.zig"),
        .target = b.graph.host,
    });
    const abi_net_host = b.createModule(.{
        .root_source_file = b.path("common/abi/net.zig"),
        .target = b.graph.host,
    });

    const abi_test_mod = b.createModule(.{
        .root_source_file = b.path("test/common/abi_test.zig"),
        .target = b.graph.host,
    });
    abi_test_mod.addImport("abi_syscall", abi_syscall_host);
    abi_test_mod.addImport("abi_fs", abi_fs_host);
    abi_test_mod.addImport("abi_net", abi_net_host);

    const abi_tests = b.addTest(.{
        .root_module = abi_test_mod,
    });
    const run_abi_tests = b.addRunArtifact(abi_tests);

    const libc_ip_host = b.createModule(.{
        .root_source_file = b.path("userspace/libc/ip.zig"),
        .target = b.graph.host,
    });
    const libc_format_host = b.createModule(.{
        .root_source_file = b.path("userspace/libc/format.zig"),
        .target = b.graph.host,
    });

    const libc_helpers_test_mod = b.createModule(.{
        .root_source_file = b.path("test/userspace/libc_helpers_test.zig"),
        .target = b.graph.host,
    });
    libc_helpers_test_mod.addImport("libc_ip", libc_ip_host);
    libc_helpers_test_mod.addImport("libc_format", libc_format_host);

    const libc_helpers_tests = b.addTest(.{
        .root_module = libc_helpers_test_mod,
    });
    const run_libc_helpers_tests = b.addRunArtifact(libc_helpers_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_memory_map_tests.step);
    test_step.dependOn(&run_physical_tests.step);
    test_step.dependOn(&run_device_registry_tests.step);
    test_step.dependOn(&run_icmp_tests.step);
    test_step.dependOn(&run_tcp_tests.step);
    test_step.dependOn(&run_curl_target_tests.step);
    test_step.dependOn(&run_dns_codec_tests.step);
    test_step.dependOn(&run_abi_tests.step);
    test_step.dependOn(&run_libc_helpers_tests.step);
}
