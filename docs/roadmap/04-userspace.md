# Phase 4 — Userspace

**Goal:** Load and run user ELF programs with a minimal Linux-compatible syscall surface, console I/O, and a shell.

**Depends on:** [Phase 3 — Kernel runtime](03-kernel-runtime.md)

**Unlocks:** [Phase 5 — I/O stack](05-io-stack.md)

---

## Checklist

- [ ] Add [`proc/process.zig`](../../src/kernel/proc/process.zig)
  - [ ] Process address space (separate page tables)
  - [ ] Per-process file descriptor table (stub OK initially)
- [ ] Add [`mm/user_loader.zig`](../../src/kernel/mm/user_loader.zig) or `proc/elf.zig`
  - [ ] Parse ELF64 PT_LOAD for user programs
  - [ ] Map user segments at correct virtual addresses
  - [ ] Set user stack and entry point
- [ ] Ring transition: user mode entry (`iretq` or equivalent)
- [ ] Implement initial syscalls (Linux-compatible numbering where practical)
  - [ ] `read` / `write`
  - [ ] `exit` / `exit_group`
  - [ ] `brk` or `mmap` (at least one for heap growth)
  - [ ] `getpid`
- [ ] Add [`drivers/tty.zig`](../../src/kernel/drivers/tty.zig)
  - [ ] Line discipline (canonical mode optional)
  - [ ] Basic ANSI escape parsing
  - [ ] Backed by serial or VGA text for now
- [ ] Add userspace build in [`build.zig`](../../build.zig)
  - [ ] Cross-compile static user programs (e.g. `hello`, `shell`)
  - [ ] Install binaries into the FAT image (`zig-out/`)
- [ ] Add minimal libc or freestanding syscall wrappers for user programs
- [ ] Shell reads input and executes programs (built-in `exit`/`help` OK)

---

## Acceptance criteria

1. **User ELF loads and runs** — `hello` prints a message from ring 3.
2. **Syscalls work from userspace** — `write` to TTY/serial without kernel panics.
3. **Process exit** reclaims address space and returns to shell or init.
4. **Shell launches a child process** and waits for completion (or simple fork-less `exec` model documented).
5. **User crash (e.g. page fault in ring 3)** is handled — kernel survives, child is terminated cleanly.
6. **End-to-end demo:** boot → shell prompt → run user program → output → return to prompt.

---

## Notes

- Full Linux ABI compatibility is a long-term goal; document deviations.
- FAT root (already used for boot) is sufficient for loading the first user binaries.
- Filesystem abstraction can be thin — open by path from FAT is acceptable for this phase.
