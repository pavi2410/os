# Phase 9 — Virtual memory and page cache

**Goal:** Extend the address space beyond `brk` with `mmap`, demand paging, and buffered file I/O via a page cache.

**Depends on:** [Phase 8 — Process environment](08-process-environment.md), [Phase 7 — Copy-on-write fork](07-copy-on-write-fork.md) (COW applies to shared/file-backed pages)

**Unlocks:** [Phase 10 — Filesystems](10-filesystems-ext2-tmpfs.md) (ext2 benefits from page cache), dynamic linking (long-term)

---

## Rationale

Today heap growth uses **`brk` only**. Phase 4 noted `mmap` as a long-term goal; it is required for:

- Large or sparse anonymous mappings
- File-backed reads without copying entire files into user buffers
- Shared mappings and future dynamic linking
- **W^X** — separate writable and executable user pages

A **page cache** decouples VFS read/write from direct block I/O and is prerequisite for efficient ext2 and procfs.

---

## Checklist

### Demand paging and faults

- [ ] Lazy allocation — map virtual pages without physical frames until first touch
- [ ] Extend [#PF handler](../../kernel/arch/x86_64/interrupts.zig) for demand-zero anonymous pages
- [ ] Stack guard page (optional but recommended) — guard below user stack
- [ ] Document interaction with existing COW fault path ([phase 7](07-copy-on-write-fork.md))

### `mmap` / `munmap` / `mprotect`

- [ ] Syscalls: `mmap`, `munmap`, `mprotect` (Linux-compatible numbers where practical)
- [ ] Anonymous private mappings (`MAP_ANONYMOUS`, `MAP_PRIVATE`)
- [ ] Fixed mapping flags (`MAP_FIXED` subset) — document supported set
- [ ] `mprotect`: enforce **W^X** for user mappings (writable XOR executable where possible)
- [ ] `fork`/`execve` behavior for mapped regions (inherit, unmap, COW as appropriate)

### Page cache

- [ ] Cache object keyed by `(block device, block/page id)` or `(inode, file offset page)`
- [ ] Read path: fault or `read()` populates cache; subsequent reads hit RAM
- [ ] Write path: dirty page tracking; flush to backing store on `fsync` or eviction
- [ ] Eviction policy (simple LRU or clock — keep first implementation small)
- [ ] Pinning for DMA or kernel buffers if needed later

### File-backed mappings (stretch within phase)

- [ ] `mmap` of regular file (`MAP_SHARED` / `MAP_PRIVATE` read-only first)
- [ ] Coherence with `write()`/`read()` through FD vs mapped view — document semantics

### Tests

- [ ] Host/unit tests for page cache lookup and eviction invariants
- [ ] Integration: `mmap` anonymous region, write, fork child sees COW copy
- [ ] Integration: read large file twice — second read faster or hits cache (optional metric)
- [ ] Integration: `mprotect` deny execute on writable page (if W^X enabled)

---

## Acceptance criteria

1. **`mmap` anonymous mapping** — program maps memory, writes, reads back correctly.
2. **`munmap`/`mprotect`** — unmap and permission changes behave predictably; bad access faults cleanly in ring 3.
3. **Page cache** — repeated reads of the same file region avoid redundant block device I/O (observable in tests or counters).
4. **COW + mmap** — forked child and parent don't clobber each other's anonymous mappings.
5. **Kernel survives** user page faults on invalid addresses; child terminated cleanly.

---

## Notes

- Full Linux `mmap` flag matrix is not required — document supported subset in [`syscall-abi.md`](../syscall-abi.md).
- File-backed `MAP_SHARED` writable mappings can wait until ext2 write path is solid ([phase 10](10-filesystems-ext2-tmpfs.md)).
- Dynamic linking (`ld.so`) stays deferred until anonymous + file-backed mmap are stable.
