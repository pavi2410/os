const std = @import("std");
const helpers = @import("build/helpers.zig");

const baseline_x86_features_add = std.Target.x86.featureSet(&.{ .popcnt, .soft_float });
const baseline_x86_features_sub = std.Target.x86.featureSet(&.{ .avx, .avx2, .sse, .sse2, .mmx });

const freestanding_x64_query: std.Target.Query = .{
    .cpu_arch = .x86_64,
    .os_tag = .freestanding,
    .abi = .none,
    .cpu_features_add = baseline_x86_features_add,
    .cpu_features_sub = baseline_x86_features_sub,
};

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    const kernel_target = b.resolveTargetQuery(freestanding_x64_query);

    const user_target = b.resolveTargetQuery(freestanding_x64_query);

    const user_optimize: std.builtin.OptimizeMode = .ReleaseSmall;

    const abi_user = helpers.AbiBundle.create(b, user_target, user_optimize);
    const common_bytes_user = helpers.exeModule(b, "common/bytes.zig", user_target, user_optimize);
    const common_view_user = helpers.exeModule(b, "common/view.zig", user_target, user_optimize);
    abi_user.attachFsView(common_view_user);

    const user_ulib = helpers.exeModule(b, "userspace/ulib/mod.zig", user_target, user_optimize);
    abi_user.attachTo(user_ulib);

    const dns_codec_user = helpers.exeModule(b, "userspace/net/dns_codec.zig", user_target, user_optimize);
    dns_codec_user.addImport("common_bytes", common_bytes_user);
    user_ulib.addImport("dns_codec", dns_codec_user);

    const std_root = helpers.exeModule(b, "userspace/std_root.zig", user_target, user_optimize);
    const time_unix_user = helpers.exeModule(b, "common/time_unix.zig", user_target, user_optimize);

    const user_deps = helpers.UserDeps{
        .target = user_target,
        .optimize = user_optimize,
        .ulib = user_ulib,
        .std_root = std_root,
    };

    const user_bin_dir: std.Build.InstallDir = .{ .custom = "userspace/bin" };
    const user_install = std.Build.Step.InstallArtifact.Options{
        .dest_dir = .{ .override = user_bin_dir },
    };

    const install_ping = helpers.addUserProgram(b, user_deps, "ping", "userspace/ping/main.zig", user_install);
    const install_ip = helpers.addUserProgram(b, user_deps, "ip", "userspace/ip/main.zig", user_install);
    const install_lscpu = helpers.addUserProgram(b, user_deps, "lscpu", "userspace/lscpu/main.zig", user_install);
    const install_lspci = helpers.addUserProgram(b, user_deps, "lspci", "userspace/lspci/main.zig", user_install);
    const install_lsblk = helpers.addUserProgram(b, user_deps, "lsblk", "userspace/lsblk/main.zig", user_install);
    const install_lsmem = helpers.addUserProgram(b, user_deps, "lsmem", "userspace/lsmem/main.zig", user_install);

    const common_tap_user = helpers.exeModule(b, "common/tap.zig", user_target, user_optimize);
    const utest_tap = helpers.exeModule(b, "userspace/utest/tap.zig", user_target, user_optimize);
    utest_tap.addImport("ulib", user_ulib);
    utest_tap.addImport("common_tap", common_tap_user);

    const utest = b.addExecutable(.{
        .name = "utest",
        .root_module = helpers.exeModule(b, "userspace/utest/main.zig", user_target, user_optimize),
    });
    utest.setLinkerScript(b.path("userspace/linker.ld"));
    utest.root_module.link_libc = false;
    utest.root_module.addImport("ulib", user_ulib);
    utest.root_module.addImport("std_root", std_root);
    utest.root_module.addImport("common_bytes", common_bytes_user);
    utest.root_module.addImport("dns_codec", dns_codec_user);
    utest.root_module.addImport("utest_tap", utest_tap);
    const utest_tests = helpers.exeModule(b, "userspace/utest/tests.zig", user_target, user_optimize);
    utest_tests.addImport("common_bytes", common_bytes_user);
    utest_tests.addImport("dns_codec", dns_codec_user);
    utest_tests.addImport("utest_tap", utest_tap);
    utest.root_module.addImport("tests", utest_tests);
    const install_utest = b.addInstallArtifact(utest, user_install);

    const shell = b.addExecutable(.{
        .name = "shell",
        .root_module = helpers.exeModule(b, "userspace/shell/main.zig", user_target, user_optimize),
    });
    shell.setLinkerScript(b.path("userspace/linker.ld"));
    shell.root_module.link_libc = false;
    shell.root_module.addImport("ulib", user_ulib);
    shell.root_module.addImport("std_root", std_root);
    shell.root_module.addImport("time_unix", time_unix_user);
    const install_shell = b.addInstallArtifact(shell, user_install);

    const dig = b.addExecutable(.{
        .name = "dig",
        .root_module = helpers.exeModule(b, "userspace/dig/main.zig", user_target, user_optimize),
    });
    dig.setLinkerScript(b.path("userspace/linker.ld"));
    dig.root_module.link_libc = false;
    dig.root_module.addImport("ulib", user_ulib);
    dig.root_module.addImport("std_root", std_root);
    dig.root_module.addImport("dns_codec", dns_codec_user);
    const install_dig = b.addInstallArtifact(dig, user_install);

    const curl = b.addExecutable(.{
        .name = "curl",
        .root_module = helpers.exeModule(b, "userspace/curl/main.zig", user_target, user_optimize),
    });
    curl.setLinkerScript(b.path("userspace/linker.ld"));
    curl.root_module.link_libc = false;
    curl.root_module.addImport("ulib", user_ulib);
    curl.root_module.addImport("std_root", std_root);
    const curl_target_user = helpers.exeModule(b, "userspace/curl/target.zig", user_target, user_optimize);
    curl_target_user.addImport("ulib", user_ulib);
    curl.root_module.addImport("target.zig", curl_target_user);
    const install_curl = b.addInstallArtifact(curl, user_install);

    b.getInstallStep().dependOn(&install_shell.step);
    b.getInstallStep().dependOn(&install_dig.step);
    b.getInstallStep().dependOn(&install_ping.step);
    b.getInstallStep().dependOn(&install_curl.step);
    b.getInstallStep().dependOn(&install_ip.step);
    b.getInstallStep().dependOn(&install_lscpu.step);
    b.getInstallStep().dependOn(&install_lspci.step);
    b.getInstallStep().dependOn(&install_lsblk.step);
    b.getInstallStep().dependOn(&install_lsmem.step);
    b.getInstallStep().dependOn(&install_utest.step);

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
    const common_acpi_sig_kernel = helpers.exeModule(b, "common/acpi_sig.zig", kernel_target, optimize);
    const common_view_kernel = helpers.exeModule(b, "common/view.zig", kernel_target, optimize);
    abi_kernel.attachFsView(common_view_kernel);
    abi_kernel.attachTo(kernel_mod);
    kernel_mod.addImport("common_bytes", common_bytes_kernel);
    kernel_mod.addImport("common_acpi_sig", common_acpi_sig_kernel);
    kernel_mod.addImport("common_view", common_view_kernel);
    kernel_mod.addImport("common_tap", helpers.exeModule(b, "common/tap.zig", kernel_target, optimize));
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

    const ulib_ip_host = helpers.hostModule(b, "userspace/ulib/ip.zig");
    const ulib_format_host = helpers.hostModule(b, "userspace/ulib/format.zig");
    const ulib_parse_host = helpers.hostModule(b, "userspace/ulib/parse.zig");

    const dns_codec_mod = helpers.hostModule(b, "userspace/net/dns_codec.zig");
    dns_codec_mod.addImport("common_bytes", host_common.bytes);

    const abi_host = helpers.AbiBundle.create(b, b.graph.host, .Debug);
    abi_host.attachFsView(host_common.view);

    const ulib_target_support_host = helpers.hostModule(b, "userspace/ulib/target_support.zig");

    const curl_target_mod = helpers.hostModule(b, "userspace/curl/target.zig");
    curl_target_mod.addImport("ulib", ulib_target_support_host);

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

    const crash_util_host_mod = helpers.hostModule(b, "kernel/proc/crash_util.zig");

    const crash_test_mod = helpers.hostTestModule(b, "test/kernel/crash_test.zig");
    crash_test_mod.addImport("crash_util", crash_util_host_mod);
    const run_crash_tests = helpers.runHostTest(b, crash_test_mod);

    const fd_table_host_mod = helpers.hostModule(b, "kernel/proc/fd_table.zig");

    const fd_table_test_mod = helpers.hostTestModule(b, "test/kernel/fd_table_test.zig");
    fd_table_test_mod.addImport("fd_table", fd_table_host_mod);
    const run_fd_table_tests = helpers.runHostTest(b, fd_table_test_mod);

    const socket_table_host_mod = helpers.hostModule(b, "kernel/net/socket/table.zig");

    const socket_table_test_mod = helpers.hostTestModule(b, "test/kernel/socket_table_test.zig");
    socket_table_test_mod.addImport("socket_table", socket_table_host_mod);
    const run_socket_table_tests = helpers.runHostTest(b, socket_table_test_mod);

    const acpi_access_test_mod = helpers.hostTestModule(b, "test/kernel/acpi_access_test.zig");
    acpi_access_test_mod.addImport("common_acpi_sig", host_common.acpi_sig);
    const run_acpi_access_tests = helpers.runHostTest(b, acpi_access_test_mod);

    const time_math_host = helpers.hostModule(b, "userspace/ulib/time_math.zig");

    const ulib_helpers_test_mod = helpers.hostTestModule(b, "test/userspace/ulib_helpers_test.zig");
    ulib_helpers_test_mod.addImport("ulib_ip", ulib_ip_host);
    ulib_helpers_test_mod.addImport("ulib_format", ulib_format_host);
    ulib_helpers_test_mod.addImport("ulib_parse", ulib_parse_host);
    const run_ulib_helpers_tests = helpers.runHostTest(b, ulib_helpers_test_mod);

    const pci_class_host = helpers.hostModule(b, "userspace/ulib/pci_class.zig");

    const pci_class_test_mod = helpers.hostTestModule(b, "test/userspace/pci_class_test.zig");
    pci_class_test_mod.addImport("pci_class", pci_class_host);
    const run_pci_class_tests = helpers.runHostTest(b, pci_class_test_mod);

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
        run_crash_tests,
        run_fd_table_tests,
        run_socket_table_tests,
        run_acpi_access_tests,
        run_icmp_tests,
        run_tcp_tests,
        run_curl_target_tests,
        run_dns_codec_tests,
        run_abi_tests,
        run_bytes_tests,
        run_view_tests,
        run_ulib_helpers_tests,
        run_pci_class_tests,
        run_time_math_tests,
    });
}
