const heap = @import("heap.zig");
const page_ref = @import("page_ref.zig");
const physical = @import("physical.zig");
const virtual = @import("virtual.zig");
const paging = @import("../arch/x86_64/paging.zig");

/// Runtime-owned memory service. Allocator implementation state migrates here
/// incrementally; this first slice centralizes lifecycle and ordering.
pub const Memory = struct {
    initialized: bool = false,

    pub fn init(self: *Memory) !void {
        physical.init();
        virtual.init();
        try heap.init();
        try page_ref.init(physical.maxPfn());
        self.initialized = true;
    }
};

/// Central address-space lifecycle API. It deliberately owns no policy about
/// process layout; callers supply user mappings and retain the returned CR3.
pub const AddressSpaceManager = struct {
    pub fn createUser() paging.MapError!u64 {
        return paging.createUserAddressSpace();
    }

    pub fn destroyUser(cr3: u64) void {
        paging.destroyUserAddressSpace(cr3) catch {};
    }

    pub fn activate(cr3: u64) void {
        paging.writeCr3(cr3);
    }

    pub fn mapUser(cr3: u64, virt: u64, phys: u64, perm: paging.Pte) paging.MapError!void {
        return paging.mapUserPageIn(cr3, virt, phys, perm);
    }

    pub fn unmapUser(cr3: u64, virt: u64) paging.MapError!void {
        return paging.unmapUserPageIn(cr3, virt);
    }

    pub fn unmapUserRange(cr3: u64, base: u64, len: u64) paging.MapError!void {
        return paging.unmapUserRangeIn(cr3, base, len);
    }
};
