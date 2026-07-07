const std = @import("std");
const helpers = @import("build/helpers.zig");

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

    const abi_user = helpers.AbiBundle.create(b, user_target, user_optimize);
    const common_bytes_user = helpers.exeModule(b, "common/bytes.zig", user_target, user_optimize);
    const common_view_user = helpers.exeModule(b, "common/view.zig", user_target, user_optimize);
    abi_user.attachFsView(common_view_user);

    const user_libc = helpers.exeModule(b, "userspace/libc/mod.zig", user_target, user_optimize);
    abi_user.attachTo(user_libc);

    const dns_codec_user = helpers.exeModule(b, "userspace/net/dns_codec.zig", user_target, user_optimize);
    dns_codec_user.addImport("common_bytes", common_bytes_user);
    user_libc.addImport("dns_codec", dns_codec_user);

    const freestanding_std = helpers.exeModule(b, "userspace/freestanding_std.zig", user_target, user_optimize);
    const time_unix_user = helpers.exeModule(b, "common/time_unix.zig", user_target, user_optimize);

    const user_deps = helpers.UserDeps{
        .target = user_target,
        .optimize = user_optimize,
        .libc = user_libc,
        .freestanding_std = freestanding_std,
    };

    const user_bin_dir: std.Build.InstallDir = .{ .custom = "userspace/bin" };
    const user_install = std.Build.Step.InstallArtifact.Options{
        .dest_dir = .{ .override = user_bin_dir },
    };

    const install_hello = helpers.addUserProgram(b, user_deps, "hello", "userspace/hello/main.zig", user_install);
    const install_ping = helpers.addUserProgram(b, user_deps, "ping", "userspace/ping/main.zig", user_install);
    const install_ip = helpers.addUserProgram(b, user_deps, "ip", "userspace/ip/main.zig", user_install);
    const install_lscpu = helpers.addUserProgram(b, user_deps, "lscpu", "userspace/lscpu/main.zig", user_install);
    const install_lspci = helpers.addUserProgram(b, user_deps, "lspci", "userspace/lspci/main.zig", user_install);
    const install_lsblk = helpers.addUserProgram(b, user_deps, "lsblk", "userspace/lsblk/main.zig", user_install);
    const install_lsmem = helpers.addUserProgram(b, user_deps, "lsmem", "userspace/lsmem/main.zig", user_install);

    const shell = b.addExecutable(.{
        .name = "shell",
        .root_module = helpers.exeModule(b, "userspace/shell/main.zig", user_target, user_optimize),
    });
    shell.setLinkerScript(b.path("userspace/linker.ld"));
    shell.root_module.addImport("libc", user_libc);
    shell.root_module.addImport("freestanding_std", freestanding_std);
    shell.root_module.addImport("time_unix", time_unix_user);
    const install_shell = b.addInstallArtifact(shell, user_install);

    const dig = b.addExecutable(.{
        .name = "dig",
        .root_module = helpers.exeModule(b, "userspace/dig/main.zig", user_target, user_optimize),
    });
    dig.setLinkerScript(b.path("userspace/linker.ld"));
    dig.root_module.addImport("libc", user_libc);
    dig.root_module.addImport("freestanding_std", freestanding_std);
    dig.root_module.addImport("dns_codec", dns_codec_user);
    const install_dig = b.addInstallArtifact(dig, user_install);

    const curl = b.addExecutable(.{
        .name = "curl",
        .root_module = helpers.exeModule(b, "userspace/curl/main.zig", user_target, user_optimize),
    });
    curl.setLinkerScript(b.path("userspace/linker.ld"));
    curl.root_module.addImport("libc", user_libc);
    curl.root_module.addImport("freestanding_std", freestanding_std);
    const curl_target_user = helpers.exeModule(b, "userspace/curl/target.zig", user_target, user_optimize);
    curl_target_user.addImport("libc", user_libc);
    curl.root_module.addImport("target.zig", curl_target_user);
    const install_curl = b.addInstallArtifact(curl, user_install);

    b.getInstallStep().dependOn(&install_hello.step);
    b.getInstallStep().dependOn(&install_shell.step);
    b.getInstallStep().dependOn(&install_dig.step);
    b.getInstallStep().dependOn(&install_ping.step);
    b.getInstallStep().dependOn(&install_curl.step);
    b.getInstallStep().dependOn(&install_ip.step);
    b.getInstallStep().dependOn(&install_lscpu.step);
    b.getInstallStep().dependOn(&install_lspci.step);
    b.getInstallStep().dependOn(&install_lsblk.step);
    b.getInstallStep().dependOn(&install_lsmem.step);

    const limine_kernel_mod = helpers.exeModule(b, "kernel/boot/limine.zig", kernel_target, optimize);

    const kernel_mod = b.createModule(.{
        .root_source_file = b.path("kernel/main.zig"),
        .target = kernel_target,
        .optimize = optimize,
        .code_model = .kernel,
    });
    kernel_mod.addImport("limine", limine_kernel_mod);

    const abi_kernel = helpers.AbiBundle.create(b, kernel_target, optimize);
    const common_bytes_kernel = helpers.exeModule(b, "common/bytes.zig", kernel_target, optimize);
    const common_view_kernel = helpers.exeModule(b, "common/view.zig", kernel_target, optimize);
    abi_kernel.attachFsView(common_view_kernel);
    abi_kernel.attachTo(kernel_mod);
    kernel_mod.addImport("common_bytes", common_bytes_kernel);
    kernel_mod.addImport("common_view", common_view_kernel);
    kernel_mod.addImport("time_unix", helpers.exeModule(b, "common/time_unix.zig", kernel_target, optimize));

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

    const host_common = helpers.HostCommon.create(b);

    const limine_mod = helpers.hostModule(b, "kernel/boot/limine.zig");

    const memory_map_host_mod = helpers.hostModule(b, "kernel/mm/memory_map.zig");
    memory_map_host_mod.addImport("limine", limine_mod);

    const memory_map_test_mod = helpers.hostTestModule(b, "test/kernel/memory_map_test.zig");
    memory_map_test_mod.addImport("memory_map", memory_map_host_mod);
    memory_map_test_mod.addImport("limine", limine_mod);
    const run_memory_map_tests = helpers.runHostTest(b, memory_map_test_mod);

    const physical_bitmap_host_mod = helpers.hostModule(b, "kernel/mm/physical_bitmap.zig");

    const physical_test_mod = helpers.hostTestModule(b, "test/kernel/physical_test.zig");
    physical_test_mod.addImport("physical_bitmap", physical_bitmap_host_mod);
    const run_physical_tests = helpers.runHostTest(b, physical_test_mod);

    const block_host_mod = helpers.hostModule(b, "kernel/drivers/block.zig");
    const net_device_host_mod = helpers.hostModule(b, "kernel/drivers/net_device.zig");

    const device_registry_test_mod = helpers.hostTestModule(b, "test/kernel/device_registry_test.zig");
    device_registry_test_mod.addImport("block", block_host_mod);
    device_registry_test_mod.addImport("net_device", net_device_host_mod);
    const run_device_registry_tests = helpers.runHostTest(b, device_registry_test_mod);

    const virtio_queue_index_host_mod = helpers.hostModule(b, "kernel/drivers/virtio_queue_index.zig");

    const virtio_queue_index_test_mod = helpers.hostTestModule(b, "test/kernel/virtio_queue_index_test.zig");
    virtio_queue_index_test_mod.addImport("virtio_queue_index", virtio_queue_index_host_mod);
    const run_virtio_queue_index_tests = helpers.runHostTest(b, virtio_queue_index_test_mod);

    const virtio_descriptor_host_mod = helpers.hostModule(b, "kernel/drivers/virtio_descriptor.zig");

    const virtio_descriptor_test_mod = helpers.hostTestModule(b, "test/kernel/virtio_descriptor_test.zig");
    virtio_descriptor_test_mod.addImport("virtio_descriptor", virtio_descriptor_host_mod);
    const run_virtio_descriptor_tests = helpers.runHostTest(b, virtio_descriptor_test_mod);

    const icmp_test_mod = helpers.hostTestModule(b, "kernel/net/icmp_test.zig");
    icmp_test_mod.addImport("common_view", host_common.view);
    const run_icmp_tests = helpers.runHostTest(b, icmp_test_mod);

    const tcp_test_mod = helpers.hostTestModule(b, "kernel/net/tcp_test.zig");
    tcp_test_mod.addImport("common_bytes", host_common.bytes);
    tcp_test_mod.addImport("common_view", host_common.view);
    const run_tcp_tests = helpers.runHostTest(b, tcp_test_mod);

    const libc_ip_host = helpers.hostModule(b, "userspace/libc/ip.zig");
    const libc_format_host = helpers.hostModule(b, "userspace/libc/format.zig");
    const libc_parse_host = helpers.hostModule(b, "userspace/libc/parse.zig");

    const dns_codec_mod = helpers.hostModule(b, "userspace/net/dns_codec.zig");
    dns_codec_mod.addImport("common_bytes", host_common.bytes);

    const abi_host = helpers.AbiBundle.create(b, b.graph.host, .Debug);
    abi_host.attachFsView(host_common.view);

    const libc_target_support_host = helpers.hostModule(b, "userspace/libc/target_support.zig");

    const curl_target_mod = helpers.hostModule(b, "userspace/curl/target.zig");
    curl_target_mod.addImport("libc", libc_target_support_host);

    const curl_target_test_mod = helpers.hostTestModule(b, "test/userspace/curl_target_test.zig");
    curl_target_test_mod.addImport("curl_target", curl_target_mod);
    const run_curl_target_tests = helpers.runHostTest(b, curl_target_test_mod);

    const dns_codec_test_mod = helpers.hostTestModule(b, "test/userspace/dns_codec_test.zig");
    dns_codec_test_mod.addImport("dns_codec", dns_codec_mod);
    const run_dns_codec_tests = helpers.runHostTest(b, dns_codec_test_mod);

    const abi_test_mod = helpers.hostTestModule(b, "test/common/abi_test.zig");
    abi_host.attachTo(abi_test_mod);
    const run_abi_tests = helpers.runHostTest(b, abi_test_mod);

    const bytes_test_mod = helpers.hostTestModule(b, "test/common/bytes_test.zig");
    bytes_test_mod.addImport("common_bytes", host_common.bytes);
    const run_bytes_tests = helpers.runHostTest(b, bytes_test_mod);

    const view_test_mod = helpers.hostTestModule(b, "test/common/view_test.zig");
    view_test_mod.addImport("common_view", host_common.view);
    const run_view_tests = helpers.runHostTest(b, view_test_mod);

    const filesystem_host_mod = helpers.hostModule(b, "kernel/fs/filesystem.zig");
    filesystem_host_mod.addImport("abi_fs", abi_host.fs);

    const filesystem_contract_test_mod = helpers.hostTestModule(b, "test/kernel/filesystem_contract_test.zig");
    filesystem_contract_test_mod.addImport("filesystem", filesystem_host_mod);
    const run_filesystem_contract_tests = helpers.runHostTest(b, filesystem_contract_test_mod);

    const syscall_user_host_mod = helpers.hostModule(b, "kernel/syscall/user.zig");

    const syscall_user_test_mod = helpers.hostTestModule(b, "test/kernel/syscall_user_test.zig");
    syscall_user_test_mod.addImport("syscall_user", syscall_user_host_mod);
    const run_syscall_user_tests = helpers.runHostTest(b, syscall_user_test_mod);

    const time_math_host = helpers.hostModule(b, "userspace/libc/time_math.zig");

    const libc_helpers_test_mod = helpers.hostTestModule(b, "test/userspace/libc_helpers_test.zig");
    libc_helpers_test_mod.addImport("libc_ip", libc_ip_host);
    libc_helpers_test_mod.addImport("libc_format", libc_format_host);
    libc_helpers_test_mod.addImport("libc_parse", libc_parse_host);
    const run_libc_helpers_tests = helpers.runHostTest(b, libc_helpers_test_mod);

    const time_math_test_mod = helpers.hostTestModule(b, "test/userspace/time_math_test.zig");
    time_math_test_mod.addImport("time_math", time_math_host);
    const run_time_math_tests = helpers.runHostTest(b, time_math_test_mod);

    const test_step = b.step("test", "Run unit tests");
    helpers.dependOnTests(test_step, &.{
        run_memory_map_tests,
        run_physical_tests,
        run_device_registry_tests,
        run_virtio_queue_index_tests,
        run_virtio_descriptor_tests,
        run_filesystem_contract_tests,
        run_syscall_user_tests,
        run_icmp_tests,
        run_tcp_tests,
        run_curl_target_tests,
        run_dns_codec_tests,
        run_abi_tests,
        run_bytes_tests,
        run_view_tests,
        run_libc_helpers_tests,
        run_time_math_tests,
    });
}
