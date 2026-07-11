const heap = @import("heap.zig");
const page_ref = @import("page_ref.zig");
const physical = @import("physical.zig");
const virtual = @import("virtual.zig");

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
