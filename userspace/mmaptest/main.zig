const std_root = @import("std_root");
pub const std_options_debug_io = std_root.std_options_debug_io;
pub const std_options = std_root.std_options;
pub const panic = @import("ulib").panic.handler;

const ulib = @import("ulib");
const tap = @import("mmaptest_tap");

export fn main(_argc: usize, _argv: [*][*]u8) callconv(.{ .x86_64_sysv = .{} }) u8 {
    _ = _argc;
    _ = _argv;

    tap.Harness.version();
    tap.Harness.plan(6);
    testAnonMapWriteRead();
    testMunmapFaultKillsChild();
    testMprotectRoWriteFaults();
    testForkAnonPrivate();
    testFileMapRead();
    testForkMmapCow();
    return tap.Harness.finish();
}

fn testAnonMapWriteRead() void {
    const len: usize = 4096;
    const ptr = ulib.syscall.mmap(
        0,
        len,
        ulib.syscall.PROT_READ | ulib.syscall.PROT_WRITE,
        ulib.syscall.MAP_PRIVATE | ulib.syscall.MAP_ANONYMOUS,
        -1,
        0,
    );
    if (ptr < 0) {
        tap.Harness.notOk("anon mmap write read", "mmap failed");
        return;
    }
    const base: [*]u8 = @ptrFromInt(@as(usize, @intCast(ptr)));
    base[0] = 0xAB;
    base[4095] = 0xCD;
    const ok = base[0] == 0xAB and base[4095] == 0xCD;
    _ = ulib.syscall.munmap(@as(usize, @intCast(ptr)), len);
    tap.Harness.check("anon mmap write read", ok);
}

fn testMunmapFaultKillsChild() void {
    const len: usize = 4096;
    const ptr = ulib.syscall.mmap(
        0,
        len,
        ulib.syscall.PROT_READ | ulib.syscall.PROT_WRITE,
        ulib.syscall.MAP_PRIVATE | ulib.syscall.MAP_ANONYMOUS,
        -1,
        0,
    );
    if (ptr < 0) {
        tap.Harness.notOk("munmap then fault kills child", "mmap failed");
        return;
    }
    const addr: usize = @intCast(ptr);
    _ = ulib.syscall.munmap(addr, len);

    const pid = ulib.process.fork();
    if (pid < 0) {
        tap.Harness.notOk("munmap then fault kills child", "fork failed");
        return;
    }
    if (pid == 0) {
        const p: *volatile u8 = @ptrFromInt(addr);
        p.* = 1;
        ulib.process.exit(0);
    }

    var status: u32 = 0;
    _ = ulib.process.wait(pid, &status, 0);
    tap.Harness.check("munmap then fault kills child", status != 0);
}

fn testMprotectRoWriteFaults() void {
    const len: usize = 4096;
    const ptr = ulib.syscall.mmap(
        0,
        len,
        ulib.syscall.PROT_READ | ulib.syscall.PROT_WRITE,
        ulib.syscall.MAP_PRIVATE | ulib.syscall.MAP_ANONYMOUS,
        -1,
        0,
    );
    if (ptr < 0) {
        tap.Harness.notOk("mprotect ro write faults", "mmap failed");
        return;
    }
    const addr: usize = @intCast(ptr);
    const base: [*]u8 = @ptrFromInt(addr);
    base[0] = 1;
    if (ulib.syscall.mprotect(addr, len, ulib.syscall.PROT_READ) < 0) {
        tap.Harness.notOk("mprotect ro write faults", "mprotect failed");
        _ = ulib.syscall.munmap(addr, len);
        return;
    }

    const pid = ulib.process.fork();
    if (pid < 0) {
        tap.Harness.notOk("mprotect ro write faults", "fork failed");
        _ = ulib.syscall.munmap(addr, len);
        return;
    }
    if (pid == 0) {
        const p: *volatile u8 = @ptrFromInt(addr);
        p.* = 2;
        ulib.process.exit(0);
    }

    var status: u32 = 0;
    _ = ulib.process.wait(pid, &status, 0);
    _ = ulib.syscall.munmap(addr, len);
    tap.Harness.check("mprotect ro write faults", status != 0);
}

fn testForkMmapCow() void {
    const len: usize = 4096;
    const ptr = ulib.syscall.mmap(
        0,
        len,
        ulib.syscall.PROT_READ | ulib.syscall.PROT_WRITE,
        ulib.syscall.MAP_PRIVATE | ulib.syscall.MAP_ANONYMOUS,
        -1,
        0,
    );
    if (ptr < 0) {
        tap.Harness.notOk("fork mmap cow", "mmap failed");
        return;
    }
    const addr: usize = @intCast(ptr);
    const base: [*]u32 = @ptrFromInt(addr);
    base[0] = 7;

    const pid = ulib.process.fork();
    if (pid < 0) {
        tap.Harness.notOk("fork mmap cow", "fork failed");
        _ = ulib.syscall.munmap(addr, len);
        return;
    }
    if (pid == 0) {
        base[0] = 8;
        ulib.process.exit(0);
    }

    var status: u32 = 0;
    _ = ulib.process.wait(pid, &status, 0);
    const ok = base[0] == 7 and status == 0;
    _ = ulib.syscall.munmap(addr, len);
    tap.Harness.check("fork mmap cow", ok);
}

fn testFileMapRead() void {
    const path: [*:0]const u8 = "/README.TXT";
    const fd = ulib.syscall.open(path, 0, 0);
    if (fd < 0) {
        tap.Harness.notOk("file mmap read", "open failed");
        return;
    }
    const fd_u: u32 = @intCast(fd);
    var buf: [16]u8 = undefined;
    const n = ulib.syscall.read(fd_u, &buf, buf.len);
    if (n <= 0) {
        tap.Harness.notOk("file mmap read", "read failed");
        _ = ulib.syscall.close(fd_u);
        return;
    }
    _ = ulib.syscall.lseek(fd_u, 0, 0);

    const ptr = ulib.syscall.mmap(
        0,
        4096,
        ulib.syscall.PROT_READ,
        ulib.syscall.MAP_PRIVATE,
        @intCast(fd),
        0,
    );
    if (ptr < 0) {
        tap.Harness.notOk("file mmap read", "mmap failed");
        _ = ulib.syscall.close(fd_u);
        return;
    }
    const mapped: [*]const u8 = @ptrFromInt(@as(usize, @intCast(ptr)));
    var ok = true;
    var i: usize = 0;
    while (i < @as(usize, @intCast(n))) : (i += 1) {
        if (mapped[i] != buf[i]) ok = false;
    }
    _ = ulib.syscall.munmap(@as(usize, @intCast(ptr)), 4096);
    _ = ulib.syscall.close(fd_u);
    tap.Harness.check("file mmap read", ok);
}

fn testForkAnonPrivate() void {
    const len: usize = 4096;
    const ptr = ulib.syscall.mmap(
        0,
        len,
        ulib.syscall.PROT_READ | ulib.syscall.PROT_WRITE,
        ulib.syscall.MAP_PRIVATE | ulib.syscall.MAP_ANONYMOUS,
        -1,
        0,
    );
    if (ptr < 0) {
        tap.Harness.notOk("fork anon private", "mmap failed");
        return;
    }
    const addr: usize = @intCast(ptr);
    const base: [*]u32 = @ptrFromInt(addr);
    base[0] = 42;

    const pid = ulib.process.fork();
    if (pid < 0) {
        tap.Harness.notOk("fork anon private", "fork failed");
        _ = ulib.syscall.munmap(addr, len);
        return;
    }
    if (pid == 0) {
        base[0] = 99;
        ulib.process.exit(0);
    }

    var status: u32 = 0;
    _ = ulib.process.wait(pid, &status, 0);
    const ok = base[0] == 42 and status == 0;
    _ = ulib.syscall.munmap(addr, len);
    tap.Harness.check("fork anon private", ok);
}
