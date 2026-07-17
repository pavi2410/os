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

    // The boot-time ELF loader intentionally keeps a small image ceiling, so
    // release images use ReleaseSmall by default. CI and diagnostics can opt
    // into the larger checked userspace binaries explicitly.
    const user_optimize = b.option(std.builtin.OptimizeMode, "user-optimize", "Optimization mode for userspace ELF programs") orelse .ReleaseSmall;

    const abi_user = helpers.AbiBundle.create(b, user_target, user_optimize);
    const common_bytes_user = helpers.exeModule(b, "common/bytes.zig", user_target, user_optimize);
    const common_hex_user = helpers.exeModule(b, "common/hex.zig", user_target, user_optimize);
    const common_mac_user = helpers.exeModule(b, "common/mac.zig", user_target, user_optimize);
    common_mac_user.addImport("common/hex", common_hex_user);
    const common_ipv4_addr_user = helpers.exeModule(b, "common/ipv4_addr.zig", user_target, user_optimize);
    const common_view_user = helpers.exeModule(b, "common/view.zig", user_target, user_optimize);
    const common_string_user = helpers.exeModule(b, "common/string.zig", user_target, user_optimize);
    const common_path_user = helpers.exeModule(b, "common/path.zig", user_target, user_optimize);
    common_path_user.addImport("string", common_string_user);
    abi_user.attachFsView(common_view_user);

    const user_ulib = helpers.exeModule(b, "userspace/ulib/mod.zig", user_target, user_optimize);
    user_ulib.addImport("common/mac", common_mac_user);
    user_ulib.addImport("common/ipv4_addr", common_ipv4_addr_user);
    user_ulib.addImport("common/string", common_string_user);
    user_ulib.addImport("common/path", common_path_user);
    abi_user.attachTo(user_ulib);

    const dns_codec_user = helpers.exeModule(b, "userspace/net/dns_codec.zig", user_target, user_optimize);
    dns_codec_user.addImport("common/bytes", common_bytes_user);
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
    utest_tap.addImport("common/tap", common_tap_user);

    const utest = b.addExecutable(.{
        .name = "utest",
        .root_module = helpers.exeModule(b, "userspace/utest/main.zig", user_target, user_optimize),
    });
    utest.setLinkerScript(b.path("userspace/linker.ld"));
    utest.root_module.link_libc = false;
    utest.root_module.addImport("ulib", user_ulib);
    utest.root_module.addImport("std_root", std_root);
    utest.root_module.addImport("common/bytes", common_bytes_user);
    utest.root_module.addImport("dns_codec", dns_codec_user);
    utest.root_module.addImport("utest_tap", utest_tap);
    const utest_tests = helpers.exeModule(b, "userspace/utest/tests.zig", user_target, user_optimize);
    utest_tests.addImport("common/bytes", common_bytes_user);
    utest_tests.addImport("dns_codec", dns_codec_user);
    utest_tests.addImport("utest_tap", utest_tap);
    utest.root_module.addImport("tests", utest_tests);
    const install_utest = b.addInstallArtifact(utest, user_install);

    const cowtest_tap = helpers.exeModule(b, "userspace/cowtest/tap.zig", user_target, user_optimize);
    cowtest_tap.addImport("ulib", user_ulib);
    cowtest_tap.addImport("common/tap", common_tap_user);

    const cowtest = b.addExecutable(.{
        .name = "cowtest",
        .root_module = helpers.exeModule(b, "userspace/cowtest/main.zig", user_target, user_optimize),
    });
    cowtest.setLinkerScript(b.path("userspace/linker.ld"));
    cowtest.root_module.link_libc = false;
    cowtest.root_module.addImport("ulib", user_ulib);
    cowtest.root_module.addImport("std_root", std_root);
    cowtest.root_module.addImport("cowtest_tap", cowtest_tap);
    const install_cowtest = b.addInstallArtifact(cowtest, user_install);

    const install_envtest = helpers.addUserProgram(b, user_deps, "envtest", "userspace/envtest/main.zig", user_install);
    const install_devtest = helpers.addUserProgram(b, user_deps, "devtest", "userspace/devtest/main.zig", user_install);
    const install_init = helpers.addUserProgram(b, user_deps, "init", "userspace/init/main.zig", user_install);

    const shell_status_user = helpers.exeModule(b, "userspace/shell/status.zig", user_target, user_optimize);
    const shell = b.addExecutable(.{
        .name = "shell",
        .root_module = helpers.exeModule(b, "userspace/shell/main.zig", user_target, user_optimize),
    });
    shell.setLinkerScript(b.path("userspace/linker.ld"));
    shell.root_module.link_libc = false;
    shell.root_module.addImport("ulib", user_ulib);
    shell.root_module.addImport("std_root", std_root);
    shell.root_module.addImport("time_unix", time_unix_user);
    shell.root_module.addImport("status", shell_status_user);
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
    b.getInstallStep().dependOn(&install_cowtest.step);
    b.getInstallStep().dependOn(&install_envtest.step);
    b.getInstallStep().dependOn(&install_devtest.step);
    b.getInstallStep().dependOn(&install_init.step);

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
    const common_hex_kernel = helpers.exeModule(b, "common/hex.zig", kernel_target, optimize);
    const common_mac_kernel = helpers.exeModule(b, "common/mac.zig", kernel_target, optimize);
    common_mac_kernel.addImport("common/hex", common_hex_kernel);
    const common_ipv4_addr_kernel = helpers.exeModule(b, "common/ipv4_addr.zig", kernel_target, optimize);
    const common_acpi_sig_kernel = helpers.exeModule(b, "common/acpi_sig.zig", kernel_target, optimize);
    const common_view_kernel = helpers.exeModule(b, "common/view.zig", kernel_target, optimize);
    const common_string_kernel = helpers.exeModule(b, "common/string.zig", kernel_target, optimize);
    const common_path_kernel = helpers.exeModule(b, "common/path.zig", kernel_target, optimize);
    common_path_kernel.addImport("string", common_string_kernel);
    abi_kernel.attachFsView(common_view_kernel);
    abi_kernel.attachTo(kernel_mod);
    kernel_mod.addImport("common/bytes", common_bytes_kernel);
    kernel_mod.addImport("common/hex", common_hex_kernel);
    kernel_mod.addImport("common/mac", common_mac_kernel);
    kernel_mod.addImport("common/ipv4_addr", common_ipv4_addr_kernel);
    kernel_mod.addImport("common/acpi_sig", common_acpi_sig_kernel);
    kernel_mod.addImport("common/view", common_view_kernel);
    kernel_mod.addImport("common/string", common_string_kernel);
    kernel_mod.addImport("common/path", common_path_kernel);
    kernel_mod.addImport("common/tap", helpers.exeModule(b, "common/tap.zig", kernel_target, optimize));
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

    const page_ref_host_mod = helpers.hostModule(b, "kernel/mm/page_ref_table.zig");

    const page_ref_test_mod = helpers.hostTestModule(b, "test/kernel/page_ref_test.zig");
    page_ref_test_mod.addImport("page_ref", page_ref_host_mod);
    const run_page_ref_tests = helpers.runHostTest(b, page_ref_test_mod);

    const vma_host_mod = helpers.hostModule(b, "kernel/mm/vma.zig");
    const vma_test_mod = helpers.hostTestModule(b, "test/kernel/vma_test.zig");
    vma_test_mod.addImport("vma", vma_host_mod);
    const run_vma_tests = helpers.runHostTest(b, vma_test_mod);

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
    icmp_test_mod.addImport("common/view", host_common.view);
    icmp_test_mod.addImport("common/hex", host_common.hex);
    icmp_test_mod.addImport("common/mac", host_common.mac);
    icmp_test_mod.addImport("common/ipv4_addr", host_common.ipv4_addr);
    const run_icmp_tests = helpers.runHostTest(b, icmp_test_mod);

    const tcp_test_mod = helpers.hostTestModule(b, "kernel/net/tcp_test.zig");
    tcp_test_mod.addImport("common/bytes", host_common.bytes);
    tcp_test_mod.addImport("common/view", host_common.view);
    tcp_test_mod.addImport("common/hex", host_common.hex);
    tcp_test_mod.addImport("common/mac", host_common.mac);
    tcp_test_mod.addImport("common/ipv4_addr", host_common.ipv4_addr);
    const run_tcp_tests = helpers.runHostTest(b, tcp_test_mod);

    const ulib_ip_host = helpers.hostModule(b, "userspace/ulib/ip.zig");
    ulib_ip_host.addImport("common/mac", host_common.mac);
    ulib_ip_host.addImport("common/ipv4_addr", host_common.ipv4_addr);
    const ulib_format_host = helpers.hostModule(b, "userspace/ulib/format.zig");
    const ulib_parse_host = helpers.hostModule(b, "userspace/ulib/parse.zig");

    const dns_codec_mod = helpers.hostModule(b, "userspace/net/dns_codec.zig");
    dns_codec_mod.addImport("common/bytes", host_common.bytes);

    const abi_host = helpers.AbiBundle.create(b, b.graph.host, .Debug);
    abi_host.attachFsView(host_common.view);

    const ulib_target_support_host = helpers.hostModule(b, "userspace/ulib/target_support.zig");
    ulib_target_support_host.addImport("common/ipv4_addr", host_common.ipv4_addr);
    ulib_target_support_host.addImport("common/mac", host_common.mac);

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

    const signal_test_mod = helpers.hostTestModule(b, "test/common/signal_test.zig");
    abi_host.attachTo(signal_test_mod);
    const run_signal_tests = helpers.runHostTest(b, signal_test_mod);

    const bytes_test_mod = helpers.hostTestModule(b, "test/common/bytes_test.zig");
    bytes_test_mod.addImport("common/bytes", host_common.bytes);
    const run_bytes_tests = helpers.runHostTest(b, bytes_test_mod);

    const hex_test_mod = helpers.hostTestModule(b, "test/common/hex_test.zig");
    hex_test_mod.addImport("common/hex", host_common.hex);
    const run_hex_tests = helpers.runHostTest(b, hex_test_mod);

    const mac_test_mod = helpers.hostTestModule(b, "test/common/mac_test.zig");
    mac_test_mod.addImport("common/mac", host_common.mac);
    const run_mac_tests = helpers.runHostTest(b, mac_test_mod);

    const ipv4_addr_test_mod = helpers.hostTestModule(b, "test/common/ipv4_addr_test.zig");
    ipv4_addr_test_mod.addImport("common/ipv4_addr", host_common.ipv4_addr);
    const run_ipv4_addr_tests = helpers.runHostTest(b, ipv4_addr_test_mod);

    const view_test_mod = helpers.hostTestModule(b, "test/common/view_test.zig");
    view_test_mod.addImport("common/view", host_common.view);
    const run_view_tests = helpers.runHostTest(b, view_test_mod);

    const string_test_mod = helpers.hostTestModule(b, "test/common/string_test.zig");
    string_test_mod.addImport("common/string", host_common.string);
    const run_string_tests = helpers.runHostTest(b, string_test_mod);

    const path_host_string = helpers.hostModule(b, "common/string.zig");
    const path_host = helpers.hostModule(b, "common/path.zig");
    path_host.addImport("string", path_host_string);
    const path_test_mod = helpers.hostTestModule(b, "test/common/path_test.zig");
    path_test_mod.addImport("common/path", path_host);
    const run_path_tests = helpers.runHostTest(b, path_test_mod);

    const filesystem_host_mod = helpers.hostModule(b, "kernel/fs/filesystem.zig");
    filesystem_host_mod.addImport("abi_fs", abi_host.fs);

    const devfs_host_mod = helpers.hostModule(b, "kernel/fs/devfs.zig");
    devfs_host_mod.addImport("abi_fs", abi_host.fs);
    devfs_host_mod.addImport("filesystem.zig", filesystem_host_mod);

    const devfs_test_mod = helpers.hostTestModule(b, "test/kernel/devfs_test.zig");
    devfs_test_mod.addImport("devfs", devfs_host_mod);
    devfs_test_mod.addImport("filesystem", filesystem_host_mod);
    const run_devfs_tests = helpers.runHostTest(b, devfs_test_mod);

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


    const pipe_host_mod = helpers.hostModule(b, "kernel/ipc/pipe.zig");

    const fd_table_host_mod = helpers.hostModule(b, "kernel/proc/fd_table.zig");
    fd_table_host_mod.addImport("../fs/devfs.zig", devfs_host_mod);
    fd_table_host_mod.addImport("../ipc/pipe.zig", pipe_host_mod);

    const fd_table_test_mod = helpers.hostTestModule(b, "test/kernel/fd_table_test.zig");
    fd_table_test_mod.addImport("fd_table", fd_table_host_mod);
    const run_fd_table_tests = helpers.runHostTest(b, fd_table_test_mod);

    const socket_table_host_mod = helpers.hostModule(b, "kernel/net/socket/table.zig");
    socket_table_host_mod.addImport("common/ipv4_addr", host_common.ipv4_addr);

    const socket_table_test_mod = helpers.hostTestModule(b, "test/kernel/socket_table_test.zig");
    socket_table_test_mod.addImport("socket_table", socket_table_host_mod);
    const run_socket_table_tests = helpers.runHostTest(b, socket_table_test_mod);

    const pipe_test_mod = helpers.hostTestModule(b, "test/kernel/pipe_table_test.zig");
    pipe_test_mod.addImport("pipe", pipe_host_mod);
    const run_pipe_tests = helpers.runHostTest(b, pipe_test_mod);

    const orphan_host_mod = helpers.hostModule(b, "kernel/proc/orphan.zig");
    const orphan_test_mod = helpers.hostTestModule(b, "test/kernel/orphan_reparent_test.zig");
    orphan_test_mod.addImport("orphan", orphan_host_mod);
    const run_orphan_tests = helpers.runHostTest(b, orphan_test_mod);

    const acpi_access_test_mod = helpers.hostTestModule(b, "test/kernel/acpi_access_test.zig");
    acpi_access_test_mod.addImport("common/acpi_sig", host_common.acpi_sig);
    const run_acpi_access_tests = helpers.runHostTest(b, acpi_access_test_mod);

    const time_math_host = helpers.hostModule(b, "userspace/ulib/time_math.zig");

    const ulib_string_host = helpers.hostModule(b, "userspace/ulib/string.zig");
    ulib_string_host.addImport("common/string", host_common.string);
    const ulib_environ_host = helpers.hostModule(b, "userspace/ulib/environ.zig");
    ulib_environ_host.addImport("string", ulib_string_host);

    const environ_test_mod = helpers.hostTestModule(b, "test/userspace/environ_test.zig");
    environ_test_mod.addImport("environ", ulib_environ_host);
    const run_environ_tests = helpers.runHostTest(b, environ_test_mod);

    const shell_line_host = helpers.hostModule(b, "userspace/shell/line.zig");
    const shell_line_test_mod = helpers.hostTestModule(b, "test/userspace/shell_line_test.zig");
    shell_line_test_mod.addImport("line", shell_line_host);
    const run_shell_line_tests = helpers.runHostTest(b, shell_line_test_mod);

    const shell_argv_host = helpers.hostModule(b, "userspace/shell/argv.zig");
    const shell_argv_test_mod = helpers.hostTestModule(b, "test/userspace/shell_argv_test.zig");
    shell_argv_test_mod.addImport("argv", shell_argv_host);
    const run_shell_argv_tests = helpers.runHostTest(b, shell_argv_test_mod);

    const shell_environ_stub = helpers.hostModule(b, "test/stub/shell_environ_stub.zig");
    const shell_status_host = helpers.hostModule(b, "userspace/shell/status.zig");
    const shell_status_test_mod = helpers.hostTestModule(b, "test/userspace/shell_status_test.zig");
    shell_status_test_mod.addImport("status", shell_status_host);
    const run_shell_status_tests = helpers.runHostTest(b, shell_status_test_mod);
    const shell_expand_host = helpers.hostModule(b, "userspace/shell/expand.zig");
    shell_expand_host.addImport("argv.zig", shell_argv_host);
    shell_expand_host.addImport("environ", shell_environ_stub);
    shell_expand_host.addImport("status", shell_status_host);

    const shell_expand_test_mod = helpers.hostTestModule(b, "test/userspace/shell_expand_test.zig");
    shell_expand_test_mod.addImport("expand", shell_expand_host);
    shell_expand_test_mod.addImport("argv", shell_argv_host);
    shell_expand_test_mod.addImport("status", shell_status_host);
    const run_shell_expand_tests = helpers.runHostTest(b, shell_expand_test_mod);

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
    const test_host_step = b.step("test-host", "Run fast host-side unit tests");
    helpers.dependOnTests(test_step, &.{
        run_memory_map_tests,
        run_page_ref_tests,
        run_vma_tests,
        run_physical_tests,
        run_device_registry_tests,
        run_virtio_queue_index_tests,
        run_virtio_descriptor_tests,
        run_filesystem_contract_tests,
        run_devfs_tests,
        run_syscall_user_tests,
        run_crash_tests,
        run_fd_table_tests,
        run_socket_table_tests,
        run_pipe_tests,
        run_orphan_tests,
        run_acpi_access_tests,
        run_icmp_tests,
        run_tcp_tests,
        run_curl_target_tests,
        run_dns_codec_tests,
        run_abi_tests,
        run_signal_tests,
        run_bytes_tests,
        run_hex_tests,
        run_mac_tests,
        run_ipv4_addr_tests,
        run_view_tests,
        run_string_tests,
        run_path_tests,
        run_environ_tests,
        run_shell_line_tests,
        run_shell_argv_tests,
        run_shell_status_tests,
        run_shell_expand_tests,
        run_ulib_helpers_tests,
        run_pci_class_tests,
        run_time_math_tests,
    });
    test_host_step.dependOn(test_step);
}
