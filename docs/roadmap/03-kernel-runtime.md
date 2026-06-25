# Phase 3 — Kernel runtime

**Goal:** Handle timer interrupts, run kernel threads, and establish the syscall entry path.

**Depends on:** [Phase 2 — Memory allocators](02-physical-and-virtual-memory.md)

**Unlocks:** [Phase 4 — Userspace](04-userspace.md)

---

## Checklist

- [x] Add interrupt controller support
  - [x] APIC (LAPIC + IOAPIC; legacy PIC masked)
  - [x] Mask/unmask IRQ helpers (`maskGsi` / `unmaskGsi`)
- [x] Add [`arch/x86_64/interrupts.zig`](../../kernel/arch/x86_64/interrupts.zig) or extend `idt.zig`
  - [x] IRQ dispatch table
  - [x] Timer interrupt handler
  - [x] EOI handling
- [x] Add timer driver (LAPIC periodic timer, PIT-calibrated)
- [x] Add [`proc/thread.zig`](../../kernel/proc/thread.zig)
  - [x] Thread struct (context, stack, state)
  - [x] Context switch (save/restore GPRs, RSP, RIP)
- [x] Add [`proc/scheduler.zig`](../../kernel/proc/scheduler.zig)
  - [x] Round-robin scheduler (timer-quantum preemption via `yieldIfRequested`)
  - [x] Idle thread
- [x] Spawn at least two kernel threads that print on serial
- [ ] Add [`syscall/`](../../kernel/syscall/) entry stub
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
