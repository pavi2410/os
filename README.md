# os

A hobby x86-64 operating system in Zig, booted with [Limine](https://github.com/Limine-Bootloader/Limine).

## Goals

* x86-64 higher-half kernel with a Linux-compatible syscall interface
* Limine bootloader (protocol base revision 6)
* Multicore threading (SMP)
* FAT32 as the sole on-disk filesystem; tmpfs for `/tmp`
* BSD-style sockets and TCP/IP networking
* Serial terminal with ANSI parsing; interactive shell
* GUI with a basic window manager (future)
* Written in Zig for safety, simplicity, and modern tooling

## Status

Boots under QEMU (including `-smp N`), runs `/BIN/INIT` as PID 1 → serial shell, and supports VirtIO disk/net, FAT32 + tmpfs, `/proc`/`/sys`, and ELF `fork`/`execve`.

| Area | Highlights |
|------|------------|
| Memory | Higher-half kernel, allocators, COW fork, `mmap`, demand paging, page cache, W^X |
| Scheduling | Preemptive RR, per-CPU run queues, SMP via Limine MP, ACPI `poweroff` |
| I/O | VirtIO-blk/net, FAT32, tmpfs, mount table, `/dev`, `/proc`, `/sys` |
| Networking | ARP, IPv4, UDP, ICMP, minimal TCP client, DNS (`dig` / `curl`) |
| Userspace | ELF64 loader, serial TTY, shell with `PATH`, pipes, redirects, `^C` |

**Next:** [testing & CI](docs/roadmap/06-testing-and-quality.md), process-env polish, then [GUI](docs/roadmap/14-gui.md). Full plan: [docs/roadmap/](docs/roadmap/). Syscall list: [docs/syscall-abi.md](docs/syscall-abi.md).

## Setup

Requires [mise](https://mise.jdx.dev), Zig (0.16+), QEMU, and Limine. [uv](https://docs.astral.sh/uv/) handles ISO/disk scripts and integration tests. OVMF is optional (UEFI boot only).

**macOS**

```bash
brew install limine qemu
mise install
eval "$(mise activate zsh)"   # add to ~/.zshrc to persist
```

**Linux / WSL**

```bash
sudo apt install qemu-system-x86 ovmf
mise install
eval "$(mise activate bash)"   # add to ~/.bashrc to persist
```

If Limine is missing from the distro, `mise run iso` downloads `limine-binary` v12.3.3 automatically.

**OVMF** (only for `mise run boot-uefi`) — copy firmware into `ovmf/` once:

```bash
# macOS
mkdir -p ovmf
cp "$(brew --prefix qemu)/share/qemu/edk2-x86_64-code.fd" ovmf/OVMF_CODE_4M.fd
dd if=/dev/zero of=ovmf/OVMF_VARS_4M.fd bs=1m count=4

# Linux
mkdir -p ovmf
cp /usr/share/OVMF/OVMF_CODE_4M.fd ovmf/
cp /usr/share/OVMF/OVMF_VARS_4M.fd ovmf/
```

## Build & run

```bash
mise run boot
```

That builds the kernel and userspace, refreshes the ISO + FAT disk, and starts QEMU with an interactive serial console. Prompt is `/> ` (or `/path> ` after `cd`).

```text
help
cat /README.TXT
ls -l /
cat /proc/cpuinfo
lscpu
export FOO=bar
curl example.com
poweroff
```

`PATH` defaults to `/BIN`. Pipes and redirects work (`echo hi | cat`, `echo hi > /TMP/OUT`). Run `mise tasks` for the full task list.

| Task | Description |
|------|-------------|
| `build` | Kernel + userspace binaries |
| `iso` / `disk` | Limine ISO / VirtIO FAT32 image |
| `boot` / `boot-uefi` | QEMU (SeaBIOS or OVMF) |
| `test` / `test-host` | Fast host unit tests |
| `test-in-guest` | Kernel + `/BIN/utest` TAP under QEMU |
| `test-shell` | Serial shell smoke + disk persistence |
| `test-smp` | QEMU `-smp` online-CPU smoke |
| `test-extended` | Network-marked diagnostics (optional) |
| `kill-qemu` / `clean` / `clean-disk` | Stop QEMU / wipe build or disk |

**Pre-merge gate**

```bash
mise run test && mise run test-in-guest && mise run test-shell
```

Rebuild ISO/disk after kernel or userspace changes — stale images can hide ABI skew. Optional SMP gate: `mise run test-smp`.

### VirtIO disk

QEMU uses `zig-out/disk.img`. If the image already exists, `mise run disk` only refreshes `/README.TXT` and `/BIN/*`; files you create at the volume root are kept. Wipe with `mise run clean-disk` (or `OS_DISK_FORCE=1`).

## Roadmap

| Phase | Status | Summary |
|-------|--------|---------|
| 0–5 | Done | Foundation through I/O stack (VirtIO, FAT32, sockets, tools) |
| 6 — Testing | **Next** | ABI guards, in-guest TAP, shell integration, CI |
| 7 — COW fork | Done | Shared mappings, write-fault promotion |
| 8 — Process env | Planned | Signals, pipes, cwd, env, PATH, init, TTY polish |
| 9 — Virtual memory | Done | `mmap`, page cache, demand paging, W^X |
| 10 — Mount / tmpfs | Done | Mount table, tmpfs, rename/symlink |
| 11 — procfs/sysfs | Done | `/proc`, `/sys` |
| 12 — Preemption | Done | Timer preemption |
| 13 — SMP | Done | Multicore bring-up, ACPI, SMP-safe kernel |
| 14 — GUI | Planned | Framebuffer, input, window manager |

Details and deferred backlog: [docs/roadmap/README.md](docs/roadmap/README.md).

## Links

* [Zig](https://ziglang.org)
* [Limine](https://github.com/Limine-Bootloader/Limine)
* [OSDev Wiki](https://wiki.osdev.org)
