# Phase 14 — GUI

**Goal:** Render a basic graphical interface on a linear framebuffer — an additive output path, not a replacement for serial.

**Depends on:** [Phase 8 — Process environment](08-process-environment.md), [Phase 13 — SMP](13-smp.md) (recommended — stable multi-core scheduler before input-heavy GUI)

**Unlocks:** Advanced window manager, userland compositor, real-hardware display bring-up

---

## Rationale

[Phase 8](08-process-environment.md) makes serial the robust control plane. SMP ([phase 13](13-smp.md)) and preemption ([phase 12](12-preemptive-scheduling.md)) stabilize scheduling before mouse/keyboard and redraw loops. GUI builds on both:

- Framebuffer from Limine GOP
- Input events routed through the same TTY/input dispatch where possible
- Serial remains required for kernel panics and daily development

---

## Checklist

### Boot and framebuffer

- [ ] Limine GOP request (base, width, height, pitch, format)
- [ ] Framebuffer driver ([`drivers/framebuffer.zig`](../../kernel/drivers/framebuffer.zig))
  - [ ] Pixel plot, fill rect, blit
  - [ ] Optional double buffering
- [ ] Basic font rendering (bitmap font)
- [ ] Optional: text-mode console on framebuffer (stretch)
- [ ] Input device nodes under `/dev` (VirtIO-input, PS/2) — extends [phase 8 devfs](08-process-environment.md)

### Input

- [ ] Mouse via VirtIO-input or PS/2
- [ ] Keyboard events to focused window (reuse TTY/input path from phase 8)

### Window manager (stretch)

- [ ] Draw windows and title bars
- [ ] Focus management (click-to-focus)
- [ ] Userland compositor or in-kernel minimal WM (decision documented)

### Tests

- [ ] Boot shows framebuffer output at native GOP resolution
- [ ] Mouse moves cursor; keyboard types into focused window
- [ ] Serial shell still works alongside GUI

---

## Acceptance criteria

1. **Framebuffer displays** kernel or WM output at native GOP resolution after boot.
2. **Mouse and keyboard** move/focus at least one on-screen window (or text console on fb).
3. **Serial console unchanged** — panics and `mise run boot` workflow still use serial first.
4. **No SMP regressions** — GUI idle/redraw does not deadlock the multi-core scheduler.

---

## Notes

- Framebuffer GUI is **not** a replacement for the serial shell — it is an additional output path.
- Bootloader GOP changes can land incrementally before the full WM.
- VirtIO GPU is out of scope unless GOP proves insufficient; start with linear framebuffer from Limine.
