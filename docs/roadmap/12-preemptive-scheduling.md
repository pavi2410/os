# Phase 12 — Preemptive scheduling

**Goal:** Move from timer-quantum cooperative scheduling to **involuntary preemption** from the LAPIC timer IRQ — required before SMP and fair multi-process behavior.

**Depends on:** [Phase 7 — Copy-on-write fork](07-copy-on-write-fork.md), [Phase 8 — Process environment](08-process-environment.md) (signals + safe syscall boundaries)

**Unlocks:** [Phase 13 — SMP](13-smp.md)

---

## Background

Since [phase 3](03-kernel-runtime.md), the LAPIC timer sets `preempt_requested`; threads honor it only at `yieldIfRequested()` boundaries ([`kernel/proc/scheduler.zig`](../../kernel/proc/scheduler.zig)). That is cooperative, not true preemption:

- A CPU-bound loop in ring 0 or a thread that never yields can starve others
- SMP reschedule IPIs assume the scheduler can force a context switch from interrupt context
- Interactive shell and network stack benefit from fair time slicing

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

- [ ] Save full thread context from timer IRQ handler (or defer to a dedicated preemption trap path)
- [ ] Safe preemption points: not while holding spinlocks that must not nest across threads
- [ ] Document which kernel paths are non-preemptible (short critical sections)
- [ ] Replace or supplement `yieldIfRequested()` with true IRQ-driven switch where safe

### Scheduler invariants

- [ ] Running thread always on correct CR3 when switched away mid-syscall (audit syscall entry/exit)
- [ ] Preemption disabled counter or equivalent for critical sections
- [ ] Idle thread still runs when all runnable threads blocked

### User-visible behavior

- [ ] CPU-bound user loop no longer freezes shell indefinitely (within one quantum)
- [ ] Timer quantum tunable; document default vs Linux-ish values
- [ ] Optional: `sched_yield` syscall stub

### Tests

- [ ] Kernel stress: two busy threads make progress without manual yield
- [ ] Integration: shell remains responsive while background busy loop runs
- [ ] No stack corruption over long preempt-heavy runs (10k+ switches)

---

## Acceptance criteria

1. **Involuntary preemption** — timer IRQ can switch threads without cooperative `yield`.
2. **Shell responsiveness** — interactive input works while another thread spins.
3. **Syscall safety** — preemption during or after syscalls does not corrupt process state.
4. **Stable under load** — 60+ seconds of timer-driven scheduling without panic.

---

## Notes

- Phase 3 deliberately deferred this; it is now a hard gate before [phase 13 (SMP)](13-smp.md).
- SMP adds IPI reschedule on top of this — get uniprocessor preemption correct first.
- GUI redraw loops ([phase 14](14-gui.md)) assume a fair scheduler.
- Soak: after landing, boot under load for 60s+ of timer-driven scheduling without panic (CI uses a shorter gate; manual soak is fine).
