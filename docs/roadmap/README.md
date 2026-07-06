# Kernel roadmap

Phased plan for kernel development after the UEFI bootloader. Complete phases in order; each file lists tasks and acceptance criteria for that milestone.

| Phase | Document | Summary |
|-------|----------|---------|
| 0 | [00-foundation.md](00-foundation.md) | Foundation — memory map, GDT/IDT, kernel stack |
| 1 | [01-page-tables-and-higher-half-kernel.md](01-page-tables-and-higher-half-kernel.md) | Page tables and higher-half kernel |
| 2 | [02-physical-and-virtual-memory.md](02-physical-and-virtual-memory.md) | Physical and virtual memory allocators |
| 3 | [03-kernel-runtime.md](03-kernel-runtime.md) | Kernel runtime — timer, threads, syscalls |
| 4 | [04-userspace.md](04-userspace.md) | Userspace — ELF loader, TTY, shell |
| 5 | [05-io-stack.md](05-io-stack.md) | I/O stack — filesystem and networking |
| 6 | [06-smp-and-gui.md](06-smp-and-gui.md) | SMP and GUI |

**Current focus:** Phase 5 — TCP/IP hardening.

See also the high-level checklist in the [project README](../../README.md#-roadmap).
