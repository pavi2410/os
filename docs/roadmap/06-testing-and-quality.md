# Phase 6 — Testing and quality

**Goal:** Catch regressions quickly — especially ABI layout drift, syscall copy paths, and shell-visible behavior — before larger refactors (COW, VFS, procfs, SMP).

**Depends on:** [Phase 5 — I/O stack](05-io-stack.md) (complete)

**Unlocks:** [Phase 7 — Copy-on-write fork](07-copy-on-write-fork.md) and all later phases

---

## Motivation

Recent work on hardware snapshot syscalls and userspace tools (`lscpu`, `lsblk`, …) exposed failures that host unit tests and integration tests should have caught earlier:

- `extern struct` field order / padding mismatches between kernel and userspace
- CPUID inline-asm register constraints producing garbage strings
- ReleaseSmall codegen (`movaps`) faulting on misaligned stack copies in `lsblk`
- Stale ISO/disk artifacts masking kernel vs userspace layout skew

Automated coverage is cheaper than manual QEMU bisection.

---

## Checklist

### Host unit tests (fast, no QEMU)

- [x] ABI layout tests in [`test/common/abi_test.zig`](../../test/common/abi_test.zig) (fs, net, hw structs)
- [ ] Expand hw ABI tests: every field offset documented in [`common/abi/hw.zig`](../../common/abi/hw.zig) comptime block
- [ ] Syscall number tests stay in sync with [`docs/syscall-abi.md`](../syscall-abi.md)
- [ ] Host test for [`kernel/syscall/user.zig`](../../kernel/syscall/user.zig) helpers (existing [`syscall_user_test`](../../test/kernel/syscall_user_test.zig))
- [ ] Optional: host-parse golden files for `/proc`-style text (prep for phase 11)

### Integration tests (QEMU + pytest)

- [x] Shell smoke test: [`test/integration/test_shell.py`](../../test/integration/test_shell.py)
- [ ] Cover `lscpu` — expect `AuthenticAMD` or `GenuineIntel`, `Architecture: x86_64`
- [ ] Cover `lspci` — at least one PCI line (`class` field)
- [ ] Cover `lsblk` — `virtio-blk` and size column
- [ ] Cover `lsmem` — header + at least one memory region line
- [ ] Cover `fork/exec` via `lscpu` (already partially there; keep after hello removal)
- [ ] Document required workflow: `zig build test && zig build && mise run iso && mise run disk` before `test-shell`

### Build and CI gate

- [ ] `mise run test` — host unit tests (already exists)
- [ ] `mise run test-shell` — integration gate before merging syscall/VFS/userspace changes
- [ ] Optional CI job (GitHub Actions): build + host tests + integration on push

### Kernel self-tests (optional, medium effort)

- [ ] Syscall round-trip thread at ring 3 (extend [`kernel/syscall/test.zig`](../../kernel/syscall/test.zig) pattern)
- [ ] Smoke `getcpuinfo` / `getblockdevices` from a kernel-launched user thread

---

## Acceptance criteria

1. **`zig build test` passes** on a clean tree and covers all shared ABI structs used across the user/kernel boundary.
2. **`mise run test-shell` passes** after a full rebuild (kernel + userspace + ISO + disk).
3. **A deliberate ABI break** (e.g. reordering a field in `common/abi/hw.zig` without updating tests) fails at compile time or in integration tests — not silently at runtime in QEMU.
4. **Contributors have a documented pre-merge checklist** in the README or this file.

---

## Notes

- Integration tests are the safety net for copy-out syscalls, ELF loading, and codegen quirks host tests cannot see.
- Prefer adding a test over adding debug prints in the kernel.
- Keep tests fast: one QEMU session per test module where possible (existing `QemuShell` pattern).
