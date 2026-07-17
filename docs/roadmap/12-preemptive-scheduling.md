# Phase 12 — Preemptive scheduling

**Goal:** Move from timer-quantum cooperative scheduling to **involuntary preemption** from the LAPIC timer IRQ — required before SMP and fair multi-process behavior.

**Status:** Done (uniprocessor)

**Depends on:** [Phase 7 — Copy-on-write fork](07-copy-on-write-fork.md), [Phase 8 — Process environment](08-process-environment.md) (signals + safe syscall boundaries)

**Unlocks:** [Phase 13 — SMP](13-smp.md)

---

## Background

Phase 3 used a LAPIC timer flag honored only at `yieldIfRequested()` boundaries. Phase 12 switches from the timer IRQ via `scheduleFromIrq()` while leaving the IRQ frame on the preempted thread’s kernel stack (`SavedContext` + existing `irq_stub` → `iretq`).

---

## Quantum

| Parameter | Value | Notes |
|-----------|-------|-------|
| LAPIC timer rate | 100 Hz | [`kernel/arch/x86_64/timer.zig`](../../kernel/arch/x86_64/timer.zig) `target_hz` |
| `time_slice_ticks` | 10 | Compile-time in [`scheduler.zig`](../../kernel/proc/scheduler.zig) |
| Effective slice | ~100 ms | Fixed round-robin; not Linux CFS |

Linux desktop defaults are often on the order of a few ms under CFS; this kernel uses a coarser fixed slice for simplicity. Tune `time_slice_ticks` at compile time (no `/proc` knob yet).

Syscalls remain non-preemptible mid-handler (SFMASK clears IF). Sticky `preempt_requested` is honored on syscall return via a brief `sti` → `yieldIfRequested` → `cli` window.

---

## Checklist

### Interrupt-context context switch

- [x] Save full thread context from timer IRQ handler (stack-preserving `SavedContext` switch)
- [x] Safe preemption points: `preempt.disable` for heap, ready-queue, and voluntary `yield`
- [x] Document which kernel paths are non-preemptible (see `scheduler.zig` / `preempt.zig`)
- [x] Replace or supplement `yieldIfRequested()` with true IRQ-driven switch where safe (`scheduleFromIrq`)

### Scheduler invariants

- [x] Running thread always on correct CR3 when switched away mid-syscall (`switchTo` activates CR3 + TSS rsp0)
- [x] Preemption disabled counter (`preempt.zig`, per-thread across switches)
- [x] Idle thread still runs when all runnable threads blocked

### User-visible behavior

- [x] CPU-bound user loop no longer freezes shell indefinitely (within one quantum)
- [x] Timer quantum tunable; document default vs Linux-ish values
- [x] Optional: `sched_yield` syscall stub (Linux number 24)

### Tests

- [x] Kernel stress: two busy threads make progress without manual yield (`/BIN/preempt`)
- [x] Integration: shell remains responsive while background busy loop runs (`test_shell` / in-guest)
- [x] No stack corruption over long preempt-heavy runs (covered by preempt TAP + soak note)

---

## Acceptance criteria

1. **Involuntary preemption** — timer IRQ can switch threads without cooperative `yield`. **Met.**
2. **Shell responsiveness** — interactive input works while another thread spins. **Met** (`/BIN/preempt`).
3. **Syscall safety** — preemption during or after syscalls does not corrupt process state. **Met** (IF off mid-syscall; sticky flag on return).
4. **Stable under load** — 60+ seconds of timer-driven scheduling without panic. **Manual soak** (CI uses shorter gate).

---

## Notes

- SMP IPI reschedule ([phase 13](13-smp.md)) builds on `scheduleFromIrq` — do not start 13 until this phase stays green on one CPU.
- GUI redraw loops ([phase 14](14-gui.md)) assume a fair scheduler.
- Soak: boot under load for 60s+ of timer-driven scheduling without panic (CI uses a shorter gate; manual soak is fine).
- Related: production fork temporarily uses eager `cloneUserAddressSpace` again until COW `shareUserAddressSpace` is fixed (boot regression from commit `6d2d458`).
