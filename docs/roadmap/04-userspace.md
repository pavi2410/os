# Phase 4 — Userspace

**Goal:** Load and run user ELF programs with a minimal Linux-compatible syscall surface, console I/O, and a shell.

**Depends on:** [Phase 3 — Kernel runtime](03-kernel-runtime.md)

**Unlocks:** [Phase 5 — I/O stack](05-io-stack.md)

---

## Checklist

- [x] Add [`proc/process.zig`](../../kernel/proc/process.zig)
  - [x] Process address space (separate page tables)
  - [x] Per-process file descriptor table (stub OK initially)
- [x] Add [`mm/user_loader.zig`](../../kernel/mm/user_loader.zig) or `proc/elf.zig`
  - [x] Parse ELF64 PT_LOAD for user programs
  - [x] Map user segments at correct virtual addresses
  - [x] Set user stack and entry point
- [x] Ring transition: user mode entry (`iretq` or equivalent)
- [x] Implement initial syscalls (Linux-compatible numbering where practical)
  - [x] `read` / `write`
  - [x] `exit` / `exit_group`
  - [x] `brk` or `mmap` (at least one for heap growth)
  - [x] `getpid`
- [x] Add [`drivers/tty.zig`](../../kernel/drivers/tty.zig)
  - [x] Line discipline (canonical mode optional)
  - [x] Basic ANSI escape parsing
  - [x] Backed by serial or VGA text for now
- [x] Add userspace build in [`build.zig`](../../build.zig)
  - [x] Cross-compile static user programs (e.g. `hello`, `shell`)
  - [x] Install binaries into the FAT image (`/BIN/*` from `zig-out/userspace/bin/`)
- [x] Add minimal libc or freestanding syscall wrappers for user programs
- [x] Shell reads input and executes programs (built-in `exit`/`help` OK)
- [ ] Linux `fork` / `execve` / `wait4` (replacing OS-specific `spawn`)

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
