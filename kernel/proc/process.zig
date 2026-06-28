const cpu = @import("../arch/x86_64/cpu.zig");
const heap = @import("../mm/heap.zig");
const paging = @import("../arch/x86_64/paging.zig");
const physical = @import("../mm/physical.zig");
const gdt = @import("../arch/x86_64/gdt.zig");
const thread = @import("thread.zig");
const user_loader = @import("../mm/user_loader.zig");
const user_entry = @import("user_entry.zig");

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

pub const FdKind = enum {
    none,
    console,
    file,
};

pub const Fd = struct {
    kind: FdKind = .none,
    vfs_handle: u32 = 0,
};

pub const max_fds = 32;

/// Per-process file descriptor table (stub for Phase 4).
pub const FdTable = struct {
    fds: [max_fds]Fd,

    pub fn init() FdTable {
        var table = FdTable{
            .fds = undefined,
        };
        for (&table.fds) |*fd| {
            fd.* = .{};
        }
        table.fds[0] = .{ .kind = .console };
        table.fds[1] = .{ .kind = .console };
        table.fds[2] = .{ .kind = .console };
        return table;
    }

    pub fn allocFd(self: *FdTable) ?usize {
        var i: usize = 3;
        while (i < max_fds) : (i += 1) {
            if (self.fds[i].kind == .none) return i;
        }
        return null;
    }
};

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

    pub fn mapUserPage(self: *const AddressSpace, virt: u64, phys: u64, flags: u64) ProcessError!void {
        paging.mapUserPageIn(self.cr3, virt, phys, flags) catch return ProcessError.OutOfMemory;
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
var zombies: [max_zombies]Zombie = @splat(.{});

const max_processes = 16;
var live: [max_processes]?*Process = .{null} ** max_processes;

var boot_cr3: u64 = 0;
var next_id: usize = 1;

pub fn init() void {
    boot_cr3 = paging.readCr3();
    thread.setActivateCr3Hook(activateForThread);
}

fn activateForThread(raw: ?*anyopaque) void {
    if (raw) |p| {
        const proc: *Process = @ptrCast(@alignCast(p));
        proc.address_space.activate();
    } else {
        paging.writeCr3(boot_cr3);
    }
}

pub fn kernelAddressSpace() AddressSpace {
    return .{ .cr3 = boot_cr3 };
}

pub fn currentProcess() ?*Process {
    const raw = thread.currentProcessPtr() orelse return null;
    return @ptrCast(@alignCast(raw));
}

pub fn setCurrent(proc: ?*Process) void {
    thread.setProcess(if (proc) |p| @ptrCast(p) else null);
}

pub fn create() ProcessError!*Process {
    return createWithParent(no_parent);
}

pub fn createWithParent(parent_id: usize) ProcessError!*Process {
    const mem = heap.kmalloc(@sizeOf(Process)) catch return ProcessError.OutOfMemory;
    const proc: *Process = @ptrCast(@alignCast(mem));
    proc.* = .{
        .id = next_id,
        .parent_id = parent_id,
        .address_space = try AddressSpace.create(),
        .fds = FdTable.init(),
        .exit_status = null,
        .state = .created,
        .brk = user_brk_base,
    };
    next_id += 1;
    try register(proc);
    return proc;
}

fn register(proc: *Process) ProcessError!void {
    for (&live) |*slot| {
        if (slot.* == null) {
            slot.* = proc;
            return;
        }
    }
    return ProcessError.TooManyProcesses;
}

fn unregister(proc: *Process) void {
    for (&live) |*slot| {
        if (slot.* == proc) {
            slot.* = null;
            return;
        }
    }
}

/// Duplicate `parent` into a new child process (Linux `fork`).
/// Uses eager page copy; see docs/roadmap/04-userspace.md before adding COW.
pub fn forkChild(parent: *Process) ProcessError!*Process {
    const child = try createWithParent(parent.id);
    errdefer destroy(child);

    paging.cloneUserAddressSpace(parent.address_space.cr3, child.address_space.cr3) catch {
        return ProcessError.OutOfMemory;
    };

    child.brk = parent.brk;
    child.fds = parent.fds;
    child.state = .created;
    return child;
}

pub fn lookup(pid: usize) ?*Process {
    for (live) |slot| {
        if (slot) |proc| {
            if (proc.id == pid) return proc;
        }
    }
    return null;
}

pub fn enqueueZombie(pid: usize, parent_id: usize, status: u32) ProcessError!void {
    for (&zombies) |*slot| {
        if (slot.in_use) continue;
        slot.* = .{
            .pid = pid,
            .parent_id = parent_id,
            .status = status,
            .in_use = true,
        };
        return;
    }
    return ProcessError.TooManyZombies;
}

pub fn reapZombie(parent_id: usize, pid: usize) ?Zombie {
    for (&zombies) |*slot| {
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
    for (&zombies) |*slot| {
        if (!slot.in_use) continue;
        if (slot.parent_id != parent_id) continue;
        if (pid >= 0 and @as(usize, @intCast(pid)) != slot.pid) continue;

        const copy = slot.*;
        slot.in_use = false;
        return copy;
    }
    return null;
}

/// True if `parent_id` still has a live or unreaped child matching `pid`.
pub fn hasChild(parent_id: usize, pid: i64) bool {
    for (live) |slot| {
        if (slot) |proc| {
            if (proc.parent_id != parent_id) continue;
            if (pid < 0) return true;
            if (@as(usize, @intCast(pid)) == proc.id) return true;
        }
    }
    for (zombies) |slot| {
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

pub fn loadElf(proc: *Process, image: []const u8) user_loader.LoadError!user_loader.LoadedImage {
    return user_loader.load(proc.address_space.cr3, image);
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
    user_entry.jumpToUser(image.entry, image.stack_top, proc.address_space.cr3);
}

/// Linux `brk`: grow the heap mapping or return the current break.
pub fn sysBrk(proc: *Process, addr: u64) i64 {
    if (addr == 0) return @bitCast(@as(i64, @intCast(proc.brk)));

    if (addr < user_brk_base) return @bitCast(@as(i64, @intCast(proc.brk)));

    const page_size = paging.page_size;
    const new_end = (addr + page_size - 1) & ~(page_size - 1);
    const old_end = (proc.brk + page_size - 1) & ~(page_size - 1);
    const heap_flags = paging.Flags.user | paging.Flags.present | paging.Flags.writable | paging.Flags.no_exec;

    if (new_end > old_end) {
        var page = old_end;
        while (page < new_end) : (page += page_size) {
            const phys = physical.allocPage() catch return @bitCast(@as(i64, @intCast(proc.brk)));
            proc.address_space.mapUserPage(page, phys, heap_flags) catch {
                return @bitCast(@as(i64, @intCast(proc.brk)));
            };
        }
    }

    proc.brk = addr;
    return @bitCast(@as(i64, @intCast(addr)));
}

/// Tear down the current user process after `exit` / `exit_group`.
pub fn terminateCurrent(status: u32) noreturn {
    const proc = currentProcess() orelse {
        while (true) cpu.hlt();
    };

    const pid = proc.id;
    const parent_id = proc.parent_id;
    proc.exit_status = status;

    if (parent_id != no_parent) {
        enqueueZombie(pid, parent_id, status) catch {};
    }

    proc.address_space.destroy();
    proc.state = .dead;
    unregister(proc);
    heap.kfree(@ptrCast(proc)) catch {};

    setCurrent(null);

    thread.exit();
}
