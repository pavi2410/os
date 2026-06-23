# Phase 6 — SMP and GUI

**Goal:** Bring up application processors, add ACPI-driven hardware discovery, and render a basic GUI on a linear framebuffer.

**Depends on:** [Phase 5 — I/O stack](05-io-stack.md)

**Unlocks:** Long-term features (full Linux ABI, advanced window manager, real hardware support)

---

## Checklist

- [ ] Use Limine MP request for AP startup
  - [ ] ACPI RSDP pointer
  - [ ] GOP framebuffer (base, width, height, pitch, format)
  - [ ] Protocol version / magic field
- [ ] Parse ACPI tables ([`arch/x86_64/acpi.zig`](../../kernel/arch/x86_64/acpi.zig))
  - [ ] RSDP → RSDT/XSDT
  - [ ] MADT (APIC entries)
  - [ ] FADT (for ACPI shutdown / timer if needed)
- [ ] Enable LAPIC and IOAPIC routing
- [ ] SMP bring-up
  - [ ] Trampoline for AP startup (low memory or dedicated region)
  - [ ] Send INIT-SIPI-SIPI or equivalent
  - [ ] Per-CPU data (current thread, idle, run queues)
  - [ ] Per-CPU timer and IPI for reschedule
- [ ] Make scheduler SMP-safe (spinlocks, per-CPU run queues)
- [ ] Framebuffer driver ([`drivers/framebuffer.zig`](../../kernel/drivers/framebuffer.zig))
  - [ ] Pixel plot, fill rect, blit
  - [ ] Optional double buffering
- [ ] Basic font rendering (bitmap font)
- [ ] Simple window manager (stretch)
  - [ ] Draw windows and title bars
  - [ ] Mouse input via VirtIO-input or PS/2
  - [ ] Keyboard events to focused window
- [ ] Userland compositor or in-kernel minimal WM (decision documented)

---

## Acceptance criteria

1. **All logical CPUs online** — serial reports N cores matching QEMU `-smp N`.
2. **Threads run on multiple CPUs** — per-CPU idle/work counters show migration or parallel execution.
3. **IPI reschedule works** — no deadlocks under load on 2+ cores.
4. **Framebuffer displays** kernel or WM output at native GOP resolution after boot.
5. **Mouse and keyboard** move/focus at least one on-screen window.
6. **ACPI shutdown or reset** works from a kernel command or syscall (clean QEMU exit).

---

## Notes

- SMP before GUI is recommended — GUI input handling is easier with a stable multi-core scheduler.
- Bootloader changes for GOP/RSDP can land incrementally before full SMP.
- Real hardware will surface edge cases; QEMU `-smp 4` is the primary test target for this phase.
