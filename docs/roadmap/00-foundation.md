# Phase 0 — Foundation

**Goal:** Take control of the CPU after UEFI handoff. Parse boot metadata and handle basic exceptions before paging.

**Depends on:** UEFI bootloader ([`src/boot/`](../../src/boot/)), [`BootInfo`](../../src/shared/boot_info.zig)

**Unlocks:** [Phase 1 — Page tables](01-page-tables-and-higher-half-kernel.md)

---

## Checklist

- [x] Thin [`main.zig`](../../src/kernel/main.zig): entry, kernel stack, call `kernel.init()`
- [x] Add [`kernel.zig`](../../src/kernel/kernel.zig) with top-level `init()` / `run()`
- [ ] Add [`mm/memory_map.zig`](../../src/kernel/mm/memory_map.zig)
  - [ ] Parse UEFI memory descriptors using `descriptor_size` from `BootInfo`
  - [ ] Classify regions: conventional, reserved, runtime, MMIO, etc.
  - [ ] Print region summary over serial
- [ ] Reserve boot-owned RAM in the map model
  - [ ] Kernel image (`0x100000` … load end)
  - [ ] Memory map buffer (`BootInfo.memory_map.entries` … `+ size`)
  - [ ] Boot info location (until moved to static storage)
- [x] Add [`arch/x86_64/cpu.zig`](../../src/kernel/arch/x86_64/cpu.zig): `cli` / `sti` / `hlt`, `rdmsr` / `wrmsr` helpers
- [x] Add fixed kernel stack in `.bss` and switch to it in `_start`
- [x] Add [`arch/x86_64/gdt.zig`](../../src/kernel/arch/x86_64/gdt.zig): minimal flat 64-bit GDT
- [x] Move [`serial.zig`](../../src/kernel/serial.zig) under `arch/x86_64/` (or `drivers/serial/`)
- [x] Add [`arch/x86_64/idt.zig`](../../src/kernel/arch/x86_64/idt.zig)
  - [x] Load IDT
  - [x] Page fault handler (print `CR2`, error code, RIP)
  - [x] General protection fault handler
  - [x] Default handler for unhandled vectors

---

## Acceptance criteria

1. **`zig build run` boots** and serial prints the UEFI memory map as a human-readable region list.
2. **Reserved regions** for the loaded kernel and memory map buffer are marked non-allocatable in the internal map model (visible in debug output).
3. **Kernel uses its own stack** — not the UEFI stack left by the bootloader.
4. **GDT and IDT are loaded** before any intentional fault testing.
5. **Deliberate null dereference or unmapped access** triggers the page fault handler and prints diagnostic info on serial instead of silently hanging.
6. **No regressions** — existing boot banner and `=== Kernel Entry ===` output still appear.

---

## Notes

- Do not implement paging in this phase.
- Parsing the memory map correctly here prevents corruption when the physical allocator lands in Phase 2.
- Host-side unit tests for map parsing logic are encouraged (`zig build test`).
