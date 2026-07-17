# Phase 9 — Virtual memory and page cache

**Goal:** Extend the address space beyond `brk` with `mmap`, demand paging, and buffered file I/O via a page cache.

**Depends on:** [Phase 8 — Process environment](08-process-environment.md), [Phase 7 — Copy-on-write fork](07-copy-on-write-fork.md) (COW applies to shared/file-backed pages)

**Unlocks:** [Phase 10 — Filesystems](10-filesystems-ext2-tmpfs.md) (ext2 benefits from page cache), dynamic linking (long-term)

**Status:** Done

---

## Rationale

Heap growth was **`brk` only**. Phase 4 noted `mmap` as a long-term goal; it is required for:

- Large or sparse anonymous mappings
- File-backed reads without copying entire files into user buffers
- Shared mappings and future dynamic linking
- **W^X** — separate writable and executable user pages

A **page cache** decouples VFS read/write from direct block I/O and is prerequisite for efficient ext2 and procfs.

---

## Checklist

### Demand paging and faults

- [x] Lazy allocation — map virtual pages without physical frames until first touch
- [x] Extend [#PF handler](../../kernel/arch/x86_64/interrupts.zig) for demand-zero anonymous pages
- [x] Stack guard page — unmapped page below user stack VMA
- [x] Document interaction with existing COW fault path ([phase 7](07-copy-on-write-fork.md)): COW first, then demand-zero / file-cache fill

### `mmap` / `munmap` / `mprotect`

- [x] Syscalls: `mmap`, `munmap`, `mprotect` (Linux-compatible numbers)
- [x] Anonymous private mappings (`MAP_ANONYMOUS`, `MAP_PRIVATE`)
- [x] Fixed mapping flags (`MAP_FIXED` subset) — documented in [`syscall-abi.md`](../syscall-abi.md)
- [x] `mprotect`: enforce **W^X** for user mappings
- [x] `fork`/`execve` behavior for mapped regions (VMA inherit, COW share, exec teardown)

### Page cache

- [x] Cache object keyed by `(FileId, page index)`
- [x] Read path: fault or `read()` populates cache; subsequent reads hit RAM
- [x] Write path: dirty page tracking; flush to backing store on `fsync` or eviction
- [x] Eviction policy (clock)
- [ ] Pinning for DMA or kernel buffers if needed later

### File-backed mappings (stretch within phase)

- [x] `mmap` of regular file (`MAP_PRIVATE` read-only)
- [x] Coherence: `read`/`write` and mapped views share page-cache frames (see Notes)

### Tests

- [x] Host/unit tests for page cache lookup and eviction invariants
- [x] Integration: `mmap` anonymous region, write, fork child sees COW copy (`mmaptest`)
- [ ] Integration: read large file twice — second read faster or hits cache (optional metric)
- [x] Integration: `mprotect` deny write on RO page (`mmaptest`)

---

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | `mmap` anonymous mapping — program maps memory, writes, reads back correctly | **Done** |
| 2 | `munmap`/`mprotect` — unmap and permission changes; bad access faults cleanly in ring 3 | **Done** |
| 3 | Page cache — repeated reads of the same file region hit RAM (counters + shared cache path) | **Done** |
| 4 | COW + mmap — forked child and parent don't clobber each other's anonymous mappings | **Done** |
| 5 | Kernel survives user page faults on invalid addresses; child terminated cleanly | **Done** |

---

## Notes

- Full Linux `mmap` flag matrix is not required — supported subset is in [`syscall-abi.md`](../syscall-abi.md).
- File-backed `MAP_SHARED` writable mappings wait until ext2 write path is solid ([phase 10](10-filesystems-ext2-tmpfs.md)).
- Dynamic linking (`ld.so`) stays deferred.
- Mapped file pages and `read`/`write` share the same page-cache frames; private writable file maps remain out of scope.
