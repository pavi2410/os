# Phase 7 — Copy-on-write fork

**Goal:** Replace eager address-space duplication in `fork` with shared read-only mappings and copy-on-write (COW) promotion on write faults.

**Depends on:** [Phase 6 — Testing and quality](06-testing-and-quality.md)

**Unlocks:** [Phase 8 — Process environment](08-process-environment.md), [Phase 13 — SMP](13-smp.md) (SMP-safe COW is required before multicore)

**Status:** Paused on a safe eager-copy fallback. The COW primitives and tests exist, but production `fork` uses `cloneUserAddressSpace` until the address-space ownership refactor restores `shareUserAddressSpace` with full guest regression coverage.

---

## Background

`fork` originally eagerly copied every mapped user page. That was intentional for the shell's `fork` → `execve` pattern but did not scale:

- Fork without immediate exec wasted memory and time
- Future daemons, pipes, and job control need cheap fork
- SMP will require COW with correct TLB shootdown anyway — better to learn COW on one CPU first

COW is implemented in [`paging.shareUserAddressSpace`](../../kernel/arch/x86_64/paging.zig) and [`kernel/mm/cow.zig`](../../kernel/mm/cow.zig), but is not currently selected by production `fork`.

---

## Checklist

### Physical page sharing

- [x] Reference count (or equivalent) on physical pages used by user mappings ([`page_ref.zig`](../../kernel/mm/page_ref.zig) / [`page_ref_table.zig`](../../kernel/mm/page_ref_table.zig))
- [ ] Restore production `fork` to map child PTEs to parent's physical pages read-only (user + present) via `shareUserAddressSpace`
- [x] Mark shared user pages in page tables (software `Pte.cow` bit)

### Page fault promotion

- [x] Extend [#PF handler](../../kernel/arch/x86_64/interrupts.zig) for user write to read-only shared page
- [x] On COW fault: allocate new physical page, copy contents, remap writable private, decrement old page refcount
- [x] Handle forked child and parent both writing the same page (two independent copies; last-ref unshares in place)

### Process memory API

- [x] Audit [`process.resetAddressSpace`](../../kernel/proc/process.zig) / `execve` — unref all COW pages via `destroyUserAddressSpace`
- [x] Audit `terminateCurrent` — release refcounts on exit
- [x] Ensure `brk` growth still uses private anonymous pages (not shared)

### execve and fork interaction

- [x] `fork` + `execve` remains the shell fast path (COW share until exec tears down the child address space)
- [ ] Optional benchmark: fork-only vs fork+exec on a larger address space

### Tests

- [x] Host/unit tests for refcount helpers ([`test/kernel/page_ref_test.zig`](../../test/kernel/page_ref_test.zig))
- [x] Integration test: fork child mutates a variable; parent value unchanged ([`userspace/cowtest/`](../../userspace/cowtest/), [`test_in_guest.py`](../../test/integration/test_in_guest.py))
- [x] Integration test: fork + exec still covered by shell suite (`lscpu` / `curl` regressions tracked under [phase 6](06-testing-and-quality.md))

---

## Acceptance criteria

1. **Fork without exec** — child modifies a page; parent sees the old contents; both survive (`cowtest`).
2. **No memory leak** — repeated fork/exec or fork/exit cycles do not exhaust physical pages (refcounted teardown on destroy/exit).
3. **User crash still contained** — page fault on invalid address terminates child, kernel survives (non-COW faults still go through existing crash path).
4. **Shell and network tools** still pass integration tests after COW lands (existing shell / in-guest suites; phase 6 tracks remaining `lscpu` flake separately).

All criteria met for uniprocessor COW.

---

## SMP note (phase 13 prep)

Uniprocessor COW first. When bringing up APs in [phase 13](13-smp.md):

- TLB shootdown on page unmap/remap
- Atomic refcount updates
- Per-CPU page fault statistics (optional)

---

## Notes

- See also [phase 4](04-userspace.md) — eager copy was temporary and has been replaced.
- Do not implement COW without phase 6 tests; faults and refcounts are easy to get wrong.
- Eager `cloneUserAddressSpace` is the current safety fallback. Remove it only after COW passes the shell, in-guest, and repeated-fork regression suites.
