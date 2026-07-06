const hal = @import("../hal.zig");
const virtual = @import("../mm/virtual.zig");
const descriptor = @import("virtio_descriptor.zig");
const virtio_pci = @import("virtio_pci.zig");
const index = @import("virtio_queue_index.zig");

pub const Error = virtio_pci.VirtioError || error{
    Timeout,
};

pub const max_queue_size = 256;

pub const desc_flags = descriptor.flags;
pub const Segment = descriptor.Segment;

pub const Desc = extern struct {
    addr: u64,
    len: u32,
    flags: u16,
    next: u16,
};

pub const AvailRing = extern struct {
    flags: u16,
    idx: u16,
    ring: [max_queue_size]u16,
};

pub const UsedElem = extern struct {
    id: u32,
    len: u32,
};

pub const UsedRing = extern struct {
    flags: u16,
    idx: u16,
    ring: [max_queue_size]UsedElem,
};

pub const Queue = struct {
    queue_index: u16 = 0,
    desc_table: *align(4096) [max_queue_size]Desc = undefined,
    avail_ring: *align(4096) AvailRing = undefined,
    used_ring: *align(4096) UsedRing = undefined,
    size: u16 = 0,
    avail_idx: u16 = 0,
    last_used_idx: u16 = 0,

    pub fn init(self: *Queue, device: *const virtio_pci.Device, queue_index: u16) Error!void {
        const desc_virt = virtual.allocPages(1) catch return Error.QueueSetupFailed;
        const avail_virt = virtual.allocPages(1) catch return Error.QueueSetupFailed;
        const used_virt = virtual.allocPages(1) catch return Error.QueueSetupFailed;

        self.desc_table = @ptrFromInt(desc_virt);
        self.avail_ring = @ptrFromInt(avail_virt);
        self.used_ring = @ptrFromInt(used_virt);

        const desc_phys = virtio_pci.physFromVirt(desc_virt) orelse return Error.QueueSetupFailed;
        const avail_phys = virtio_pci.physFromVirt(avail_virt) orelse return Error.QueueSetupFailed;
        const used_phys = virtio_pci.physFromVirt(used_virt) orelse return Error.QueueSetupFailed;

        for (&self.desc_table.*) |*entry| entry.* = .{ .addr = 0, .len = 0, .flags = 0, .next = 0 };
        self.avail_ring.* = .{ .flags = 0, .idx = 0, .ring = undefined };
        self.used_ring.* = .{ .flags = 0, .idx = 0, .ring = undefined };
        self.queue_index = queue_index;
        self.avail_idx = 0;
        self.last_used_idx = 0;
        self.size = try device.setupQueue(queue_index, desc_phys, avail_phys, used_phys, max_queue_size);
    }

    pub fn submit(self: *Queue, desc_index: u16) void {
        const ring_slot = index.slot(self.size, self.avail_idx);
        self.avail_ring.ring[ring_slot] = desc_index;
        self.avail_idx = index.advance(self.avail_idx);
        memoryBarrier();
        self.avail_ring.idx = self.avail_idx;
    }

    pub fn writeChain(self: *Queue, start_index: u16, segments: []const Segment) void {
        var i: usize = 0;
        while (i < segments.len) : (i += 1) {
            const desc_index: u16 = start_index + @as(u16, @intCast(i));
            const has_next = i + 1 < segments.len;
            self.desc_table[desc_index] = .{
                .addr = segments[i].phys,
                .len = segments[i].len,
                .flags = descriptor.descriptorFlags(has_next, segments[i].writable),
                .next = if (has_next) desc_index + 1 else 0,
            };
        }
    }

    pub fn notify(self: *const Queue, device: *const virtio_pci.Device) void {
        device.notifyQueue(self.queue_index);
    }

    pub fn hasUsed(self: *const Queue) bool {
        return index.hasUsed(self.usedIdx(), self.last_used_idx);
    }

    pub fn popUsed(self: *Queue) UsedElem {
        memoryBarrier();
        const used = self.used_ring.ring[index.slot(self.size, self.last_used_idx)];
        self.last_used_idx = index.advance(self.last_used_idx);
        return used;
    }

    pub fn waitUsed(self: *Queue, device: *const virtio_pci.Device) Error!UsedElem {
        var spins: usize = 0;
        while (!self.hasUsed()) {
            device.ackInterrupt();
            hal.processor.relaxInterruptible();
            spins += 1;
            if (spins > 10_000_000) return Error.Timeout;
        }

        const used = self.popUsed();
        device.ackInterrupt();
        return used;
    }

    fn usedIdx(self: *const Queue) u16 {
        const ptr: *const volatile u16 = @ptrCast(@alignCast(&self.used_ring.idx));
        return ptr.*;
    }
};

fn memoryBarrier() void {
    asm volatile ("" ::: .{ .memory = true });
}
