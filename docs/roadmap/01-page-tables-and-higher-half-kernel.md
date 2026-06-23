# Phase 1 — Page tables and higher-half kernel

**Goal:** Link and run the kernel from a high canonical virtual address with a working virtual memory model. Boot-time paging is handled by Limine (HHDM + higher-half load); this phase adds kernel link layout, address helpers, and eventually kernel-owned page table helpers for runtime mapping.

**Depends on:** [Phase 0 — Foundation](00-foundation.md)

**Unlocks:** [Phase 2 — Memory allocators](02-physical-and-virtual-memory.md)

---

## Checklist

### Higher-half link and boot handoff

- [x] Choose higher-half base — `0xFFFFFFFF80000000` (Limine top 2 GiB / kernel code model) in [`kernel/mm/address.zig`](../../kernel/mm/address.zig)
- [x] Update [`linker.ld`](../../linker.ld) for higher-half virtual addresses (`.limine_requests`, page-aligned segments)
- [x] Update [`build.zig`](../../build.zig) link settings — `.code_model = .kernel` + linker script (no `image_base`; VA comes from `linker.ld`)
- [x] Boot paging and higher-half entry — Limine loads the kernel at its linked VA and sets up HHDM (replaces manual `CR3` / identity-map bootstrap)
- [x] Request HHDM offset from Limine and store it in [`kernel/mm/address.zig`](../../kernel/mm/address.zig) (`physToVirt` / `virtToPhys`)
- [x] Verify serial MMIO (`0x3F8`) works after Limine handoff
- [x] Document VA ↔ PA layout in [`kernel/mm/address.zig`](../../kernel/mm/address.zig)
- [x] `zig build run` succeeds with no triple-fault on boot

### Kernel-owned paging (remaining)

- [ ] Add [`arch/x86_64/paging.zig`](../../kernel/arch/x86_64/paging.zig)
  - [ ] 4-level page table types (PML4 → PDPT → PD → PT)
  - [ ] `mapPage` / `unmapPage` helpers
  - [ ] Page flag helpers (present, writable, no-exec, huge page optional)
- [ ] Verify kernel `.text` runs from the higher-half — print RIP in debug output
- [ ] Deliberate page fault on an unmapped address — confirm Phase 0 IDT handler fires
- [ ] Account page-table / boot mapping memory in the memory map model (e.g. mark `bootloader_reclaimable` regions non-allocatable)

---

## Acceptance criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Kernel `.text` runs from the higher-half (RIP in high canonical range) | Pending — add RIP check |
| 2 | Serial output works after handoff | **Done** |
| 3 | Deliberate page fault caught by Phase 0 IDT handler | Pending |
| 4 | No unnecessary low identity map in kernel page tables | **N/A** — Limine owns boot page tables; kernel does not install an identity map |
| 5 | `zig build run` succeeds with no triple-fault | **Done** |
| 6 | Page table memory not treated as free RAM | Pending |

---

## Notes

- Limine loads the executable at its **linked virtual address**; the ELF is not relocated to a fixed physical base.
- Limine provides HHDM (base revision 6): only selected memory-map region types are mapped — there is no full low-memory identity map.
- Kernel-owned `paging.zig` helpers are still needed for runtime mapping (allocators, user pages) in Phase 2+, but not for the boot transition.
- Keep paging helpers free of allocator dependencies (use preallocated or boot-time static tables for now).
