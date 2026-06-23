# Phase 2 — Physical and virtual memory

**Goal:** Allocate and free physical pages and back a kernel heap with page mappings.

**Depends on:** [Phase 1 — Page tables](01-page-tables-and-higher-half-kernel.md)

**Unlocks:** [Phase 3 — Kernel runtime](03-kernel-runtime.md)

---

## Checklist

- [ ] Add [`mm/physical.zig`](../../src/kernel/mm/physical.zig)
  - [ ] Bitmap or buddy allocator over conventional RAM
  - [ ] Honor reserved regions from Phase 0 (kernel, map buffer, page tables)
  - [ ] `allocPage()` / `freePage()` API
- [ ] Add [`mm/virtual.zig`](../../src/kernel/mm/virtual.zig)
  - [ ] Kernel virtual address space manager
  - [ ] `mapPages` / `unmapPages` using Phase 1 paging helpers
  - [ ] Track kernel virtual allocations
- [ ] Add [`mm/heap.zig`](../../src/kernel/mm/heap.zig)
  - [ ] `kmalloc` / `kfree` (or `kalloc` / `kfree`) on top of virtual pages
  - [ ] Minimum alignment support (16 bytes for general use)
- [ ] Wire allocators in `kernel.init()` after memory map parsing
- [ ] Add debug commands or serial prints: total/free/used page counts
- [ ] Add host-side tests for pure allocator logic (bitmap/buddy)

---

## Acceptance criteria

1. **`allocPage()` returns 4 KiB-aligned physical pages** from conventional memory only.
2. **Reserved regions are never allocated** — kernel image and memory map buffer remain intact after 1000+ alloc/free cycles.
3. **`kmalloc(n)` returns usable memory** for varying sizes (single page and multi-page).
4. **`kfree` paired with `kmalloc`** does not leak or double-free in a stress loop (debug counters match).
5. **No corruption** — serial output and memory map buffer remain valid after allocator stress.
6. **Host tests pass** for allocator logic (`zig build test`).

---

## Notes

- Physical allocator must be built before any subsystem that calls `kmalloc`.
- Consider a simple bump allocator as a temporary bootstrap if the full heap is not ready yet — remove before closing this phase.
- Future user address spaces will reuse `virtual.zig`; keep kernel-only assumptions explicit for now.
