//! Intrusive FIFO ready queue for the scheduler.
//! `T` must have a field `ready_next: ?*T`. No heap allocation.

/// Intrusive FIFO. Safe to call from IRQ once callers hold appropriate locks /
/// preempt-disable (queue itself does not allocate).
pub fn ReadyQueue(comptime T: type) type {
    return struct {
        head: ?*T = null,
        tail: ?*T = null,

        const Self = @This();

        pub fn push(self: *Self, item: *T) void {
            item.ready_next = null;
            if (self.tail) |tail| {
                tail.ready_next = item;
                self.tail = item;
            } else {
                self.head = item;
                self.tail = item;
            }
        }

        pub fn pop(self: *Self) ?*T {
            const item = self.head orelse return null;
            self.head = item.ready_next;
            if (self.head == null) self.tail = null;
            item.ready_next = null;
            return item;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.head == null;
        }
    };
}
