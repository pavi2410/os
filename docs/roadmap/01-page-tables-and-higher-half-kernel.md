# Phase 1 — Page tables and higher-half kernel

**Goal:** Install kernel-owned page tables and link/run the kernel from a high canonical virtual address.

**Depends on:** [Phase 0 — Foundation](00-foundation.md)

**Unlocks:** [Phase 2 — Memory allocators](02-physical-and-virtual-memory.md)

---

## Checklist

- [ ] Choose higher-half base (e.g. `0xFFFF800000000000` + physical offset)
- [ ] Update [`linker.ld`](../../linker.ld) for higher-half virtual addresses
- [ ] Update [`build.zig`](../../build.zig) `image_base` / link settings if needed
- [ ] Add [`arch/x86_64/paging.zig`](../../kernel/arch/x86_64/paging.zig)
  - [ ] 4-level page table types (PML4 → PDPT → PD → PT)
  - [ ] `mapPage` / `unmapPage` helpers
  - [ ] Page flag helpers (present, writable, no-exec, huge page optional)
- [ ] Build initial page tables at boot
  - [ ] Map kernel physical frames to higher-half virtual addresses
  - [ ] Temporary identity map for low memory during transition (if needed)
- [ ] Load `CR3` and jump to higher-half code (or enable mapping before `_start` continues)
- [ ] Verify serial MMIO (`0x3F8`) remains mapped after transition
- [ ] Tear down unnecessary identity mappings once higher-half is stable
- [ ] Document final VA ↔ PA layout in code comments or this doc

---

## Acceptance criteria

1. **Kernel `.text` runs from the higher-half** — debug output confirms RIP is in the high canonical range.
2. **Serial output works** after the paging transition (same messages as Phase 0).
3. **Deliberate page fault** on an unmapped high-half address is caught by the Phase 0 IDT handler.
4. **Low identity map removed** except regions still required (e.g. MMIO, boot structures until Phase 2 reserves them).
5. **`zig build run` succeeds** with no QEMU triple-fault on boot.
6. **Page table memory** is accounted for in the memory map model (not treated as free RAM).

---

## Notes

- The bootloader currently loads the kernel at physical `0x100000`. Paging maps those frames — it does not relocate the ELF.
- UEFI page tables are fully replaced; do not assume firmware mappings persist.
- Keep paging helpers free of allocator dependencies (use preallocated or boot-time static tables for now).
