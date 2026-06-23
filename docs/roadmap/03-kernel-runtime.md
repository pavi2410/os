# Phase 3 — Kernel runtime

**Goal:** Handle timer interrupts, run kernel threads, and establish the syscall entry path.

**Depends on:** [Phase 2 — Memory allocators](02-physical-and-virtual-memory.md)

**Unlocks:** [Phase 4 — Userspace](04-userspace.md)

---

## Checklist

- [ ] Add interrupt controller support
  - [ ] Legacy PIC **or** APIC (LAPIC recommended for SMP path)
  - [ ] Mask/unmask IRQ helpers
- [ ] Add [`arch/x86_64/interrupts.zig`](../../src/kernel/arch/x86_64/interrupts.zig) or extend `idt.zig`
  - [ ] IRQ dispatch table
  - [ ] Timer interrupt handler
  - [ ] EOI handling
- [ ] Add timer driver (PIT for simplicity, or APIC timer)
- [ ] Add [`proc/thread.zig`](../../src/kernel/proc/thread.zig)
  - [ ] Thread struct (context, stack, state)
  - [ ] Context switch (save/restore GPRs, RSP, RIP)
- [ ] Add [`proc/scheduler.zig`](../../src/kernel/proc/scheduler.zig)
  - [ ] Round-robin or cooperative scheduler
  - [ ] Idle thread
- [ ] Spawn at least two kernel threads that print on serial
- [ ] Add [`syscall/`](../../src/kernel/syscall/) entry stub
  - [ ] Choose mechanism: `syscall`/`sysret`, `sysenter`, or `int 0x80`
  - [ ] Register convention documented (match future Linux ABI target)
  - [ ] Minimal handler table (e.g. debug `write`, `exit`)

---

## Acceptance criteria

1. **Timer IRQ fires at a steady interval** — visible via serial tick counter or LED-style output.
2. **Two or more kernel threads alternate** execution without manual yielding only (timer-preempted if preemptive).
3. **Context switch preserves correctness** — no stack corruption over 10,000+ switches.
4. **Syscall entry and return** works from a test kernel thread (can be a fake "user" stack for now).
5. **Unhandled IRQ** logs vector number and does not crash silently.
6. **`zig build run` remains stable** for at least 60 seconds of timer-driven scheduling.

---

## Notes

- SMP is out of scope here; design with per-CPU data in mind but run single-core first.
- Syscall machinery can be tested from ring 0 with a simulated user stack before real userspace in Phase 4.
- Document the chosen syscall ABI in `docs/` when frozen.
