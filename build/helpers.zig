const std = @import("std");

pub fn exeModule(
    b: *std.Build,
    root: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path(root),
        .target = target,
        .optimize = optimize,
    });
}

pub fn hostModule(b: *std.Build, root: []const u8) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path(root),
        .target = b.graph.host,
    });
}

pub const AbiBundle = struct {
    syscall: *std.Build.Module,
    fs: *std.Build.Module,
    net: *std.Build.Module,
    hw: *std.Build.Module,

    pub fn create(
        b: *std.Build,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
    ) AbiBundle {
        return .{
            .syscall = exeModule(b, "common/abi/syscall.zig", target, optimize),
            .fs = exeModule(b, "common/abi/fs.zig", target, optimize),
            .net = exeModule(b, "common/abi/net.zig", target, optimize),
            .hw = exeModule(b, "common/abi/hw.zig", target, optimize),
        };
    }

    pub fn attachTo(self: AbiBundle, mod: *std.Build.Module) void {
        mod.addImport("abi_syscall", self.syscall);
        mod.addImport("abi_fs", self.fs);
        mod.addImport("abi_net", self.net);
        mod.addImport("abi_hw", self.hw);
    }

    pub fn attachFsView(self: AbiBundle, view: *std.Build.Module) void {
        self.fs.addImport("common_view", view);
    }
};

pub const UserDeps = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    ulib: *std.Build.Module,
    std_root: *std.Build.Module,
};

fn wireUserExe(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    deps: UserDeps,
) void {
    exe.setLinkerScript(b.path("userspace/linker.ld"));
    exe.root_module.link_libc = false;
    exe.root_module.addImport("ulib", deps.ulib);
    exe.root_module.addImport("std_root", deps.std_root);
}

pub fn addUserProgram(
    b: *std.Build,
    deps: UserDeps,
    name: []const u8,
    main_path: []const u8,
    install_opts: std.Build.Step.InstallArtifact.Options,
) *std.Build.Step.InstallArtifact {
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = exeModule(b, main_path, deps.target, deps.optimize),
    });
    wireUserExe(b, exe, deps);
    return b.addInstallArtifact(exe, install_opts);
}

pub fn runHostTest(b: *std.Build, root: *std.Build.Module) *std.Build.Step.Run {
    return b.addRunArtifact(b.addTest(.{ .root_module = root }));
}

pub fn hostTestModule(b: *std.Build, test_path: []const u8) *std.Build.Module {
    return hostModule(b, test_path);
}

pub const HostCommon = struct {
    bytes: *std.Build.Module,
    hex: *std.Build.Module,
    mac: *std.Build.Module,
    ipv4_addr: *std.Build.Module,
    acpi_sig: *std.Build.Module,
    view: *std.Build.Module,

    pub fn create(b: *std.Build) HostCommon {
        const hex = hostModule(b, "common/hex.zig");
        const mac = hostModule(b, "common/mac.zig");
        mac.addImport("common_hex", hex);
        return .{
            .bytes = hostModule(b, "common/bytes.zig"),
            .hex = hex,
            .mac = mac,
            .ipv4_addr = hostModule(b, "common/ipv4_addr.zig"),
            .acpi_sig = hostModule(b, "common/acpi_sig.zig"),
            .view = hostModule(b, "common/view.zig"),
        };
    }
};

pub fn dependOnTests(test_step: *std.Build.Step, runs: []const *std.Build.Step.Run) void {
    for (runs) |run| {
        test_step.dependOn(&run.step);
    }
}
