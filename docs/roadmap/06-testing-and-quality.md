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
- [x] Host test for [`kernel/syscall/user.zig`](../../kernel/syscall/user.zig) helpers ([`syscall_user_test`](../../test/kernel/syscall_user_test.zig), wired in `build.zig`)
- [ ] Optional: host-parse golden files for `/proc`-style text (prep for phase 11)

### In-guest TAP tests (QEMU + pytest, target codegen)

- [x] Shared TAP writer: [`common/tap.zig`](../../common/tap.zig)
- [x] Kernel boot suite: [`kernel/boot/tap_suite.zig`](../../kernel/boot/tap_suite.zig) (VFS readme read, UDP/DNS reply, physical pages free)
- [x] Userspace runner: [`userspace/utest/`](../../userspace/utest/) on `/BIN/utest` (bytes + dns_codec cases)
- [x] TAP parser + pytest: [`test/integration/tap_parser.py`](../../test/integration/tap_parser.py), [`test/integration/test_in_guest.py`](../../test/integration/test_in_guest.py)
- [x] `mise run test-in-guest` task (depends on `iso` + `disk`; one boot for kernel TAP, one for `utest`)
- [ ] Extend `/BIN/utest` with more modules (view, ulib helpers, dirent64 wire layout)
- [ ] Ring-3 syscall smoke via `utest` or a dedicated `/BIN/*` helper (bootstrap ring-0 `syscall` crashes QEMU)

### Integration tests (QEMU + pytest)

- [x] Shell smoke test: [`test/integration/test_shell.py`](../../test/integration/test_shell.py)
- [x] Per-case pytest reporting (class-scoped `shell_session`; one QEMU boot for smoke, one for persistence)
- [x] Cover `lscpu` — PATH/fork/exec smoke test asserts `Architecture:` and QEMU remains alive for subsequent cases
- [ ] Cover `lspci` — at least one PCI line (`class` field)
- [ ] Cover `lsblk` — `virtio-blk` and size column
- [ ] Cover `lsmem` — header + at least one memory region line
- [x] Cover `fork/exec` via `lscpu` — covered by the PATH lookup smoke test
- [x] Document required workflow (see [Pre-merge checklist](#pre-merge-checklist) below)

### Build and CI gate

- [x] `mise run test` — host unit tests (`zig build test`)
- [x] `mise run test-in-guest` — kernel + userspace TAP gate
- [x] `mise run test-shell` — shell integration task (defined)
- [ ] Optional CI job (GitHub Actions): build + host tests + `test-in-guest` + `test-shell` on push

### Kernel self-tests (optional, medium effort)

- [~] Boot-time self-checks — replaced ad-hoc VFS/UDP log lines with structured TAP in `tap_suite` (see in-guest section)
- [ ] Syscall round-trip thread at ring 3 (extend [`kernel/syscall/test.zig`](../../kernel/syscall/test.zig) pattern; ring-0 bootstrap caller is unsafe)
- [ ] Smoke `getcpuinfo` / `getblockdevices` from a kernel-launched user thread

---

## Pre-merge checklist

Run on a clean tree before merging syscall, VFS, or userspace changes:

```bash
mise run test              # host unit tests (fast)
mise run build
mise run iso
mise run disk
mise run test-in-guest     # kernel TAP + /BIN/utest (target codegen)
mise run test-shell        # shell smoke + disk persistence
```

If integration tests fail after code changes, rebuild ISO and disk — stale artifacts can mask kernel/userspace skew.

---

## Acceptance criteria

1. **`zig build test` passes** on a clean tree and covers all shared ABI structs used across the user/kernel boundary.
2. **`mise run test-in-guest` passes** after a full rebuild (kernel + userspace + ISO + disk).
3. **`mise run test-shell` passes** after a full rebuild.
4. **A deliberate ABI break** (e.g. reordering a field in `common/abi/hw.zig` without updating tests) fails at compile time or in integration tests — not silently at runtime in QEMU.
5. **Contributors use the pre-merge checklist** above (also linked from README when phase 6 closes).

---

## Notes

- **Three layers:** host unit tests (fast, ABI/logic) → in-guest TAP (target codegen, serial parse) → shell integration (end-to-end behavior).
- Integration tests are the safety net for copy-out syscalls, ELF loading, and codegen quirks host tests cannot see.
- Prefer adding a test over adding debug prints in the kernel.
- Keep tests fast: one QEMU session per pytest module where possible (`QemuShell` + module-scoped fixtures).
- TAP output uses `--- TAP kernel ---` / `--- TAP kernel end ---` markers so pytest can extract kernel results from mixed serial logs.
