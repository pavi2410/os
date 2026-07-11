const cpu = @import("../arch/x86_64/cpu.zig");
const heap = @import("../mm/heap.zig");
const paging = @import("../arch/x86_64/paging.zig");
const physical = @import("../mm/physical.zig");
const gdt = @import("../arch/x86_64/gdt.zig");
const thread = @import("thread.zig");
const user_loader = @import("../mm/user_loader.zig");
const page_ref = @import("../mm/page_ref.zig");
const user_mode = @import("../arch/x86_64/user.zig");
const fd_table = @import("fd_table.zig");
const fd_cleanup = @import("fd_cleanup.zig");
const fd_retain = @import("fd_retain.zig");
const path_mod = @import("common/path");
const signal_mod = @import("signal.zig");
const proc_types = @import("types.zig");

pub const cwd_max_len = path_mod.default_cap;
pub const Cwd = path_mod.Path(cwd_max_len);

pub const ProcessError = error{
    OutOfMemory,
    NotImplemented,
    TooManyZombies,
    TooManyProcesses,
};

pub const State = enum {
    created,
    running,
    zombie,
    dead,
};

/// `parent_id` uses 0 when a process has no parent (init shell).
pub const no_parent: usize = 0;

/// Linux-style user virtual layout constants for later ELF loading.
pub const user_stack_top = user_loader.user_stack_top;
pub const user_stack_pages = user_loader.user_stack_pages;
pub const user_brk_base: u64 = 0x0000000000400000;
pub const user_brk_limit: u64 = user_loader.user_stack_top -
    @as(u64, @intCast(user_stack_pages + 1)) * paging.page_size;

pub const Fd = fd_table.Fd;
pub const FdTable = fd_table.FdTable;
pub const max_fds = fd_table.max_fds;

pub const AddressSpace = struct {
    cr3: u64,

    pub fn create() ProcessError!AddressSpace {
        const cr3 = paging.createUserAddressSpace() catch return ProcessError.OutOfMemory;
        return .{ .cr3 = cr3 };
    }

    pub fn destroy(self: *AddressSpace) void {
        if (self.cr3 == 0) return;
        if (paging.readCr3() == self.cr3) {
            paging.writeCr3(boot_cr3);
        }
        paging.destroyUserAddressSpace(self.cr3) catch {};
        self.cr3 = 0;
    }

    pub fn activate(self: *const AddressSpace) void {
        paging.writeCr3(self.cr3);
    }

    pub fn mapUserPage(self: *const AddressSpace, virt: u64, phys: u64, perm: paging.Pte) ProcessError!void {
        paging.mapUserPageIn(self.cr3, virt, phys, perm) catch return ProcessError.OutOfMemory;
    }
};

pub const Process = struct {
    id: usize,
    parent_id: usize,
    address_space: AddressSpace,
    fds: FdTable,
    exit_status: ?u32,
    state: State,
    brk: u64,
    cwd: Cwd,
    signals: signal_mod.SignalState,

    pub fn destroy(self: *Process) void {
        self.address_space.destroy();
        self.state = .dead;
        heap.kfree(@ptrCast(self)) catch {};
    }
};

/// Exit status retained until the parent reaps via `wait4` (commit 4).
pub const Zombie = struct {
    pid: usize = 0,
    parent_id: usize = no_parent,
    status: u32 = 0,
    in_use: bool = false,
};

const max_zombies = 16;
const max_processes = 16;

/// Owns process identity and lifecycle registries. Scheduler integration will
/// migrate to this table directly in the next slice.
/// Runtime-owned process lifecycle service.
pub const ProcessManager = struct {
    zombies: [max_zombies]Zombie = @splat(.{}),
    live: [max_processes]?*Process = .{null} ** max_processes,
    next_id: usize = 1,

    pub fn lookup(self: *const ProcessManager, pid: usize) ?*Process {
        for (self.live) |slot| {
            if (slot) |proc| if (proc.id == pid) return proc;
        }
        return null;
    }

    fn register(self: *ProcessManager, proc: *Process) ProcessError!void {
        for (&self.live) |*slot| {
            if (slot.* == null) {
                slot.* = proc;
                return;
            }
        }
        return ProcessError.TooManyProcesses;
    }

    fn unregister(self: *ProcessManager, proc: *Process) void {
        for (&self.live) |*slot| {
            if (slot.* == proc) {
                slot.* = null;
                return;
            }
        }
    }

    pub fn enqueueZombie(self: *ProcessManager, pid: usize, parent_id: usize, status: u32) ProcessError!void {
        for (&self.zombies) |*slot| {
            if (slot.in_use) continue;
            slot.* = .{ .pid = pid, .parent_id = parent_id, .status = status, .in_use = true };
            return;
        }
        return ProcessError.TooManyZombies;
    }

    pub fn reapZombieAny(self: *ProcessManager, parent_id: usize, pid: isize) ?Zombie {
        for (&self.zombies) |*slot| {
            if (!slot.in_use or slot.parent_id != parent_id) continue;
            if (pid >= 0 and @as(usize, @intCast(pid)) != slot.pid) continue;
            const zombie = slot.*;
            slot.in_use = false;
            return zombie;
        }
        return null;
    }
};
var default_table: ProcessManager = .{};
var table: *ProcessManager = &default_table;

pub fn install(next: *ProcessManager) void {
    table = next;
    table.* = .{};
}

var boot_cr3: u64 = 0;

pub fn init() void {
    table.* = .{};
    boot_cr3 = paging.readCr3();
    paging.initKernelAddressSpace(boot_cr3);
    thread.setActivateCr3Hook(activateForThread);
}

fn activateForThread(id: ?proc_types.Id) void {
    if (id) |pid| {
        if (lookup(pid)) |proc| proc.address_space.activate() else paging.writeCr3(boot_cr3);
    } else {
        paging.writeCr3(boot_cr3);
    }
}

pub fn kernelAddressSpace() AddressSpace {
    return .{ .cr3 = boot_cr3 };
}

pub fn currentProcess() ?*Process {
    const id = thread.currentProcessId() orelse return null;
    return lookup(id);
}

pub fn setCurrent(proc: ?*Process) void {
    thread.setProcess(if (proc) |p| p.id else null);
}

pub fn create() ProcessError!*Process {
    return createWithParent(no_parent);
}

pub fn createWithParent(parent_id: usize) ProcessError!*Process {
    const mem = heap.kmalloc(@sizeOf(Process)) catch return ProcessError.OutOfMemory;
    const proc: *Process = @ptrCast(@alignCast(mem));
    const cwd = Cwd.root();
    proc.* = .{
        .id = table.next_id,
        .parent_id = parent_id,
        .address_space = try AddressSpace.create(),
        .fds = FdTable.init(),
        .exit_status = null,
        .state = .created,
        .brk = user_brk_base,
        .cwd = cwd,
        .signals = signal_mod.SignalState.init(),
    };
    table.next_id += 1;
    try table.register(proc);
    return proc;
}

fn register(proc: *Process) ProcessError!void {
    return table.register(proc);
}

fn unregister(proc: *Process) void {
    table.unregister(proc);
}

/// Duplicate `parent` into a new child process (Linux `fork`).
pub fn forkChild(parent: *Process) ProcessError!*Process {
    const child = try createWithParent(parent.id);
    errdefer destroy(child);

    paging.cloneUserAddressSpace(parent.address_space.cr3, child.address_space.cr3) catch {
        return ProcessError.OutOfMemory;
    };

    child.brk = parent.brk;
    child.fds = parent.fds;
    if (!fd_retain.retainAll(&child.fds)) {
        child.fds = FdTable.init();
        return ProcessError.OutOfMemory;
    }
    child.cwd = parent.cwd;
    child.state = .created;
    signal_mod.inheritFromParent(child, parent);
    return child;
}

/// Current working directory (no trailing slash except root).
pub fn cwdSlice(proc: *const Process) []const u8 {
    return proc.cwd.slice();
}

pub fn setCwd(proc: *Process, path: []const u8) ProcessError!void {
    proc.cwd.set(path) catch return ProcessError.OutOfMemory;
}

/// Resolve `path` against the process cwd into `buf`.
pub fn resolvePath(proc: *const Process, path: []const u8, buf: []u8) ProcessError![]const u8 {
    return path_mod.resolveAgainst(cwdSlice(proc), path, buf) catch return ProcessError.OutOfMemory;
}

pub fn lookup(pid: usize) ?*Process {
    return table.lookup(pid);
}

pub fn enqueueZombie(pid: usize, parent_id: usize, status: u32) ProcessError!void {
    return table.enqueueZombie(pid, parent_id, status);
}

pub fn reapZombie(parent_id: usize, pid: usize) ?Zombie {
    for (&table.zombies) |*slot| {
        if (!slot.in_use) continue;
        if (slot.parent_id != parent_id) continue;
        if (slot.pid != pid) continue;

        const copy = slot.*;
        slot.in_use = false;
        return copy;
    }
    return null;
}

/// `pid == -1` waits for any child of `parent_id`; otherwise match a specific pid.
pub fn reapZombieAny(parent_id: usize, pid: isize) ?Zombie {
    return table.reapZombieAny(parent_id, pid);
}

/// True if `parent_id` still has a live or unreaped child matching `pid`.
pub fn hasChild(parent_id: usize, pid: i64) bool {
    for (table.live) |slot| {
        if (slot) |proc| {
            if (proc.parent_id != parent_id) continue;
            if (pid < 0) return true;
            if (@as(usize, @intCast(pid)) == proc.id) return true;
        }
    }
    for (table.zombies) |slot| {
        if (!slot.in_use) continue;
        if (slot.parent_id != parent_id) continue;
        if (pid < 0) return true;
        if (@as(usize, @intCast(pid)) == slot.pid) return true;
    }
    return false;
}

pub fn destroy(proc: *Process) void {
    if (currentProcess() == proc) setCurrent(null);
    unregister(proc);
    proc.destroy();
}

pub fn loadElf(
    proc: *Process,
    image: []const u8,
    argv: []const []const u8,
    envp: []const []const u8,
) user_loader.LoadError!user_loader.LoadedImage {
    return user_loader.load(proc.address_space.cr3, image, argv, envp);
}

/// Drop all user mappings and allocate a fresh address space (for `execve`).
pub fn resetAddressSpace(proc: *Process) ProcessError!void {
    proc.address_space.destroy();
    proc.address_space = try AddressSpace.create();
}

pub fn enterUser(proc: *Process, image: user_loader.LoadedImage, kernel_stack_top: u64) noreturn {
    gdt.setKernelStack(kernel_stack_top);
    setCurrent(proc);
    proc.state = .running;
    user_mode.enter(image.entry, image.stack_top, proc.address_space.cr3);
}

/// Linux `brk`: grow the heap mapping or return the current break.
pub fn sysBrk(proc: *Process, addr: u64) i64 {
    if (addr == 0) return @bitCast(@as(i64, @intCast(proc.brk)));

    if (addr < user_brk_base or addr >= user_brk_limit) return @bitCast(@as(i64, @intCast(proc.brk)));

    const page_size = paging.page_size;
    const new_end = (addr + page_size - 1) & ~(page_size - 1);
    const old_end = (proc.brk + page_size - 1) & ~(page_size - 1);
    const heap_flags = paging.Pte.user_heap;

    if (new_end > old_end) {
        var page = old_end;
        while (page < new_end) : (page += page_size) {
            const phys = physical.allocPage() catch return @bitCast(@as(i64, @intCast(proc.brk)));
            proc.address_space.mapUserPage(page, phys, heap_flags) catch {
                return @bitCast(@as(i64, @intCast(proc.brk)));
            };
            page_ref.retain(phys) catch {
                return @bitCast(@as(i64, @intCast(proc.brk)));
            };
        }
    }

    proc.brk = addr;
    return @bitCast(@as(i64, @intCast(addr)));
}

/// Tear down the current user process after `exit` / `exit_group` or fatal signal.
pub fn terminateCurrent(wait_status: u32) noreturn {
    const proc = currentProcess() orelse {
        while (true) cpu.hlt();
    };

    const pid = proc.id;
    const parent_id = proc.parent_id;
    proc.exit_status = wait_status;

    signal_mod.onProcessExit(pid);

    if (parent_id != no_parent) {
        enqueueZombie(pid, parent_id, wait_status) catch {};
        signal_mod.notifyChildExit(parent_id);
    }

    fd_cleanup.closeAll(&proc.fds);
    proc.address_space.destroy();
    proc.state = .dead;
    unregister(proc);
    heap.kfree(@ptrCast(proc)) catch {};

    setCurrent(null);

    thread.exit();
}
