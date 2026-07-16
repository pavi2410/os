//! Orphan reparenting helpers (host-testable).

/// Userspace init process id (first `process.create()`).
pub const init_pid: usize = 1;

/// If `parent_id` is the dying process, return init; otherwise unchanged.
pub fn adoptParent(parent_id: usize, dying_pid: usize) usize {
    if (parent_id == dying_pid) return init_pid;
    return parent_id;
}

/// Rewrite parent ids that pointed at `dying_pid` to init.
/// Returns how many entries were changed.
pub fn reparentParentIds(parent_ids: []usize, dying_pid: usize) usize {
    var changed: usize = 0;
    for (parent_ids) |*pid| {
        const next = adoptParent(pid.*, dying_pid);
        if (next != pid.*) {
            pid.* = next;
            changed += 1;
        }
    }
    return changed;
}
