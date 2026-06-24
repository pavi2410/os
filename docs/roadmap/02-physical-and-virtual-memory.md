# Phase 2 — Physical and virtual memory

**Goal:** Allocate and free physical pages and back a kernel heap with page mappings.

**Depends on:** [Phase 1 — Page tables](01-page-tables-and-higher-half-kernel.md)

**Unlocks:** [Phase 3 — Kernel runtime](03-kernel-runtime.md)

---

## Checklist

- [x] Add [`mm/physical.zig`](../../kernel/mm/physical.zig)
  - [x] Bitmap or buddy allocator over conventional RAM
  - [x] Honor reserved regions from Phase 0 (kernel, map buffer, page tables)
  - [x] `allocPage()` / `freePage()` API
- [x] Add [`mm/virtual.zig`](../../kernel/mm/virtual.zig)
  - [x] Kernel virtual address space manager
  - [x] `mapPages` / `unmapPages` using Phase 1 paging helpers
  - [x] Track kernel virtual allocations
- [x] Add [`mm/heap.zig`](../../kernel/mm/heap.zig)
  - [x] `kmalloc` / `kfree` (or `kalloc` / `kfree`) on top of virtual pages
  - [x] Minimum alignment support (16 bytes for general use)
- [x] Wire allocators in `kernel.init()` after memory map parsing
- [x] Add debug commands or serial prints: total/free/used page counts
- [x] Add host-side tests for pure allocator logic (bitmap/buddy)

---

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | `allocPage()` returns 4 KiB-aligned physical pages from conventional memory only | **Done** |
| 2 | Reserved regions are never allocated — kernel image and memory map buffer remain intact after 1000+ alloc/free cycles | **Done** |
| 3 | `kmalloc(n)` returns usable memory for varying sizes (single page and multi-page) | **Done** |
| 4 | `kfree` paired with `kmalloc` does not leak or double-free in a stress loop (debug counters match) | **Done** |
| 5 | No corruption — serial output and memory map buffer remain valid after allocator stress | **Done** |
| 6 | Host tests pass for allocator logic (`zig build test`) | **Done** |

---

## Notes

- Physical allocator must be built before any subsystem that calls `kmalloc`.
- Consider a simple bump allocator as a temporary bootstrap if the full heap is not ready yet — remove before closing this phase.
- Future user address spaces will reuse `virtual.zig`; keep kernel-only assumptions explicit for now.
