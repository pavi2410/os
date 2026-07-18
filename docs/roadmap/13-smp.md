# Phase 13 — SMP

**Goal:** Bring up application processors and make the kernel scheduler, memory management, and COW paths safe on multiple CPUs.

**Depends on:** [Phase 7 — Copy-on-write fork](07-copy-on-write-fork.md), [Phase 12 — Preemptive scheduling](12-preemptive-scheduling.md), [Phase 11 — procfs and sysfs](11-procfs-and-sysfs.md) (recommended)

**Unlocks:** [Phase 14 — GUI](14-gui.md), long-term real-hardware bring-up

---

## Checklist

### ACPI and boot services

- [x] Use Limine MP request for AP startup
- [x] ACPI RSDP pointer from bootloader
- [x] Parse ACPI tables ([`kernel/acpi/`](../../kernel/acpi/))
  - [x] RSDP → RSDT/XSDT
  - [x] MADT (APIC entries)
  - [x] FADT (for ACPI shutdown / timer if needed)
- [x] Enable LAPIC and IOAPIC routing

### SMP bring-up

- [x] Trampoline for AP startup (Limine MP `goto_address`; no hand-rolled INIT-SIPI)
- [x] Send INIT-SIPI-SIPI or equivalent (via Limine MP)
- [x] Per-CPU data (current thread, idle, run queues)
- [x] Per-CPU timer and IPI for reschedule (builds on [phase 12](12-preemptive-scheduling.md))
- [x] Make scheduler SMP-safe (spinlocks, per-CPU run queues)
- [x] COW + TLB shootdown on all cores (extends [phase 7](07-copy-on-write-fork.md))
- [x] Page cache and mmap locking (extends [phase 9](09-virtual-memory-and-page-cache.md))

### Tests

- [x] QEMU `-smp 2` and `-smp 4` smoke tests
- [x] Integration: parallel shell commands or kernel stress threads on multiple CPUs
- [x] No refcount or TLB leaks under fork/exec load on SMP

---

## Acceptance criteria

1. **All logical CPUs online** — serial reports N cores matching QEMU `-smp N`.
2. **Threads run on multiple CPUs** — per-CPU idle/work counters show migration or parallel execution.
3. **IPI reschedule works** — no deadlocks under load on 2+ cores.
4. **COW fork** remains correct with concurrent writers on different cores.
5. **ACPI shutdown or reset** works from a kernel command or syscall (clean QEMU exit).

---

## Notes

- Complete [phase 7 (COW)](07-copy-on-write-fork.md) and [phase 12 (preemption)](12-preemptive-scheduling.md) on one CPU before SMP.
- Keep serial as the primary debug console; GUI is [phase 14](14-gui.md).
- Real hardware will surface edge cases; QEMU `-smp 4` is the primary test target.
- GOP / framebuffer setup belongs in phase 14, not here.
- Limine MP replaces hand-rolled INIT-SIPI: APs are parked until `goto_address` is written.
- Shell `poweroff` uses `reboot(2)` → ACPI S5 / QEMU ports `0x604` / `0xB004`.
