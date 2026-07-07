# Phase 7 — Copy-on-write fork

**Goal:** Replace eager address-space duplication in `fork` with shared read-only mappings and copy-on-write (COW) promotion on write faults.

**Depends on:** [Phase 6 — Testing and quality](06-testing-and-quality.md)

**Unlocks:** [Phase 8 — Process environment](08-process-environment.md), [Phase 13 — SMP](13-smp.md) (SMP-safe COW is required before multicore)

---

## Background

Today `fork` eagerly copies every mapped user page ([`kernel/proc/fork.zig`](../../kernel/proc/fork.zig), [`kernel/mm/user_loader.zig`](../../kernel/mm/user_loader.zig)). That was intentional for the shell's `fork` → `execve` pattern but does not scale:

- Fork without immediate exec wastes memory and time
- Future daemons, pipes, and job control need cheap fork
- SMP will require COW with correct TLB shootdown anyway — better to learn COW on one CPU first

---

## Checklist

### Physical page sharing

- [ ] Reference count (or equivalent) on physical pages used by user mappings
- [ ] `fork` maps child PTEs to parent's physical pages read-only (user + present)
- [ ] Mark shared user pages in page tables (software bit or separate tracking structure)

### Page fault promotion

- [ ] Extend [#PF handler](../../kernel/arch/x86_64/interrupts.zig) for user write to read-only shared page
- [ ] On COW fault: allocate new physical page, copy contents, remap writable private, decrement old page refcount
- [ ] Handle forked child and parent both writing the same page (two independent copies)

### Process memory API

- [ ] Audit [`process.resetAddressSpace`](../../kernel/proc/process.zig) / `execve` — unref all COW pages
- [ ] Audit `terminateCurrent` — release refcounts on exit
- [ ] Ensure `brk` growth still uses private anonymous pages (not shared)

### execve and fork interaction

- [ ] `fork` + `execve` remains the shell fast path (no regression in launch latency)
- [ ] Optional benchmark: fork-only vs fork+exec on a larger address space

### Tests

- [ ] Host/unit tests for refcount helpers where possible
- [ ] Integration test: fork child mutates a variable; parent value unchanged
- [ ] Integration test: fork + exec still runs `lscpu` / `curl`

---

## Acceptance criteria

1. **Fork without exec** — child modifies a page; parent sees the old contents; both survive.
2. **No memory leak** — repeated fork/exec or fork/exit cycles do not exhaust physical pages.
3. **User crash still contained** — page fault on invalid address terminates child, kernel survives.
4. **Shell and network tools** still pass integration tests after COW lands.

---

## SMP note (phase 13 prep)

Uniprocessor COW first. When bringing up APs in [phase 13](13-smp.md):

- TLB shootdown on page unmap/remap
- Atomic refcount updates
- Per-CPU page fault statistics (optional)

---

## Notes

- See also phase 4 note in [`04-userspace.md`](04-userspace.md) — eager copy was temporary.
- Do not implement COW without phase 6 tests; faults and refcounts are easy to get wrong.
