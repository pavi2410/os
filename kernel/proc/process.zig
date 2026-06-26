const heap = @import("../mm/heap.zig");
const paging = @import("../arch/x86_64/paging.zig");
const physical = @import("../mm/physical.zig");
const gdt = @import("../arch/x86_64/gdt.zig");
const thread = @import("thread.zig");
const user_loader = @import("../mm/user_loader.zig");
const user_entry = @import("user_entry.zig");

pub const ProcessError = error{
    OutOfMemory,
};

pub const State = enum {
    created,
    running,
    zombie,
    dead,
};

/// Linux-style user virtual layout constants for later ELF loading.
pub const user_stack_top = user_loader.user_stack_top;
pub const user_stack_pages = user_loader.user_stack_pages;
pub const user_brk_base: u64 = 0x0000000000400000;

pub const FdKind = enum {
    none,
    console,
};

pub const Fd = struct {
    kind: FdKind = .none,
};

pub const max_fds = 32;

/// Per-process file descriptor table (stub for Phase 4).
pub const FdTable = struct {
    fds: [max_fds]Fd,

    pub fn init() FdTable {
        var table = FdTable{
            .fds = .{.{}} ** max_fds,
        };
        table.fds[0] = .{ .kind = .console };
        table.fds[1] = .{ .kind = .console };
        table.fds[2] = .{ .kind = .console };
        return table;
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

var boot_cr3: u64 = 0;
var next_id: usize = 1;
var current: ?*Process = null;

pub fn init() void {
    boot_cr3 = paging.readCr3();
}

pub fn kernelAddressSpace() AddressSpace {
    return .{ .cr3 = boot_cr3 };
}

pub fn currentProcess() ?*Process {
    return current;
}

pub fn setCurrent(proc: ?*Process) void {
    current = proc;
}

pub fn create() ProcessError!*Process {
    const mem = heap.kmalloc(@sizeOf(Process)) catch return ProcessError.OutOfMemory;
    const proc: *Process = @ptrCast(@alignCast(mem));
    proc.* = .{
        .id = next_id,
        .address_space = try AddressSpace.create(),
        .fds = FdTable.init(),
        .exit_status = null,
        .state = .created,
        .brk = user_brk_base,
    };
    next_id += 1;
    return proc;
}

pub fn destroy(proc: *Process) void {
    if (current == proc) current = null;
    proc.destroy();
}

pub fn loadElf(proc: *Process, image: []const u8) user_loader.LoadError!user_loader.LoadedImage {
    return user_loader.load(proc.address_space.cr3, image);
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
    const proc = current orelse {
        thread.exit();
    };
    proc.exit_status = status;
    proc.state = .zombie;
    paging.writeCr3(kernelAddressSpace().cr3);
    setCurrent(null);
    thread.exit();
}
