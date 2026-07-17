# os

**A hobby operating system** in Zig, targeting x86-64 with [Limine](https://github.com/Limine-Bootloader/Limine), aiming for Linux ABI compatibility, multicore support, filesystems, networking, and eventually a GUI.

## Current status

The kernel boots under QEMU, starts userspace `/BIN/INIT` as PID 1 (which spawns the serial shell), reads and writes files on a VirtIO FAT32 disk, runs ELF programs from `/BIN` via `fork`/`execve`, and has a small VirtIO-net TCP/IP stack.

**Working today**

* Higher-half kernel with page tables, physical/virtual/heap allocators
* APIC (LAPIC + IOAPIC), LAPIC timer, round-robin scheduler, `syscall`/`sysret`
* ELF64 user program loader, ring-3 execution, serial TTY (canonical mode + basic ANSI)
* Syscalls: `read`, `write`, `open` (`O_CREAT`, `O_TRUNC`, `O_APPEND`), `close`, `lseek`, `stat`, `brk`, `getpid`, `fork` (copy-on-write), `execve`, `wait4`, `unlink`, `mkdir`, `rmdir`, `getdents64`, `clock_gettime`, `exit`/`exit_group`
* PCI enumeration (legacy I/O ports on QEMU q35), VirtIO-blk read/write, FAT32 VFS (read/write/create/truncate/append)
* VirtIO-net with ARP, IPv4, UDP, ICMP echo, minimal TCP client sockets, and DNS A-record resolution
* Userspace programs on the VirtIO FAT disk (`/README.TXT`, `/BIN/INIT`, `/BIN/SHELL`, `/BIN/dig`, …)
* Boot chain: kernel → `/BIN/INIT` (PID 1) → `/BIN/SHELL` (interactive serial shell)
* Serial shell with modular builtins: `help`, `exit`, `pid`, `echo`, `cat`, `ls`, `write`, `rm`, `mkdir`, `rmdir`, `cd`, `pwd`, `date`
* Disk image sync preserves user-created files across `mise run boot` (see [disk notes](#virtio-disk))
* [mise](https://mise.jdx.dev) tasks for build, ISO, disk, QEMU boot, and integration tests

**Next up** (see [docs/roadmap/](docs/roadmap/))

Phase 6 — testing and quality; then process environment (IPC/cwd/init/devfs), virtual memory, mount/tmpfs, procfs, preemption, SMP, and GUI.

## 🚀 Goals

* x86-64 architecture
* Limine bootloader (protocol base revision 6)
* Modern 64-bit higher-half kernel
* Linux-compatible syscall interface
* Multicore threading (SMP)
* FAT32 filesystem (sole on-disk FS; tmpfs for `/tmp`)
* BSD-style sockets and TCP/IP networking
* Simple terminal with ANSI parsing
* GUI with basic window manager (future)
* Written in Zig for safety, simplicity, and modern tooling

## 🛠 Toolchain

* [mise](https://mise.jdx.dev) — pins Zig, Python, uv, and defines project tasks (`mise.toml`)
* Zig (v0.16+ recommended)
* [uv](https://docs.astral.sh/uv/) — Python tooling: ISO/disk image tasks (`pycdlib`, `pyfatfs`), integration tests (`pytest`, `pexpect`)
* [Limine](https://github.com/Limine-Bootloader/Limine) — bootloader and ISO tooling
* QEMU — `qemu-system-x86_64`
* OVMF — optional, only for `mise run boot-uefi`

### macOS

Install [Homebrew](https://brew.sh) and mise, then:

```bash
brew install limine qemu
mise install
eval "$(mise activate zsh)"   # add to ~/.zshrc to persist
```

For UEFI boot testing (`mise run boot-uefi`), copy OVMF firmware into the project (one-time):

```bash
mkdir -p ovmf
cp "$(brew --prefix qemu)/share/qemu/edk2-x86_64-code.fd" ovmf/OVMF_CODE_4M.fd
dd if=/dev/zero of=ovmf/OVMF_VARS_4M.fd bs=1m count=4
```

### Linux / WSL

```bash
sudo apt install qemu-system-x86 ovmf
mise install
eval "$(mise activate bash)"   # add to ~/.bashrc to persist
```

If Limine is not available from your distro, `mise run iso` downloads the official
`limine-binary` release (v12.3.3) automatically.

For UEFI boot testing (`mise run boot-uefi`), copy OVMF firmware into the project (one-time):

```bash
mkdir -p ovmf
cp /usr/share/OVMF/OVMF_CODE_4M.fd ovmf/
cp /usr/share/OVMF/OVMF_VARS_4M.fd ovmf/
```

## 💻 Building & Running

This project uses mise tasks for build, ISO, disk, and QEMU workflows. Run `mise tasks` to list everything.

| Task | Description |
|------|-------------|
| `mise run build` | Build kernel (`zig-out/bin/`) and userspace programs (`zig-out/userspace/bin/`) |
| `mise run iso` | Build bootable Limine ISO (`zig-out/os.iso`) via Python |
| `mise run disk` | Create or update FAT32 VirtIO disk (`zig-out/disk.img`) via Python/pyfatfs |
| `mise run boot` | ISO + disk + QEMU (SeaBIOS, interactive serial) |
| `mise run boot-uefi` | Same, under OVMF/UEFI |
| `mise run test` | Host-side kernel unit tests (`test/kernel/`, no QEMU) |
| `mise run test-shell` | Serial shell integration test (pytest + pexpect, turn-by-turn) |
| `mise run kill-qemu` | Stop a stuck QEMU instance |
| `mise run clean` | Remove `zig-out/` and `.zig-cache/` |
| `mise run clean-disk` | Delete `disk.img` to force a full reformat on next boot |

Quick start:

```bash
mise run boot
```

At the shell prompt (`/> ` at root, `/path> ` after `cd`), try:

```text
help
cat /README.TXT
ls -l /
write /NOTES.TXT hello
write -a /NOTES.TXT world
cat /NOTES.TXT
lscpu
ip addr
ip route
dig example.com
curl example.com
```

Use full paths for file builtins (`cat`, `ls`, `write`). Programs in `/BIN` can be launched by name (e.g. `lscpu`).

Host unit tests (no QEMU):

```bash
mise run test
# or: zig build test
```

Tests live under `test/kernel/` (memory map parsing, physical page bitmap).

Serial shell integration test (boots QEMU twice — smoke cases, then disk persistence):

```bash
mise run test-shell
# or: uv sync --all-groups && uv run pytest test/integration -v
```

The integration harness drives the shell turn-by-turn (sync on the `path> ` prompt) via `test/integration/`. First run creates `.venv/` through `uv sync`.

### VirtIO disk

QEMU uses a VirtIO block device backed by `zig-out/disk.img`.

* If `disk.img` **already exists**, `mise run disk` only refreshes `/README.TXT` and `/BIN/*` — files you create at the volume root (e.g. with `write`) are **kept** across reboots. Updates use `scripts/create_disk.py` (pyfatfs) and do not mount the image on the host.
* Run `mise run clean-disk` (or set `OS_DISK_FORCE=1`) to wipe the image and start fresh.
* If VFS behaves oddly after a failed setup, recreate with `clean-disk` then `mise run boot`.

## 📝 Roadmap

Detailed phase docs live in [docs/roadmap/](docs/roadmap/).

| Phase | Status | Summary |
|-------|--------|---------|
| 0 — Foundation | Done | Memory map, GDT/IDT, kernel stack |
| 1 — Page tables | Done | Higher-half kernel |
| 2 — Memory | Done | Physical, virtual, and heap allocators |
| 3 — Kernel runtime | Done | APIC, timer, threads, scheduler, syscalls |
| 4 — Userspace | Done | ELF loader, TTY, shell, fork/exec |
| 5 — I/O stack | Done | VirtIO, FAT32, TCP/UDP, sockets, `ip`/`curl`/`dig`, hw tools |
| 6 — Testing | **Next** | ABI tests, shell integration tests, CI gate |
| 7 — COW fork | Done | Shared mappings, write fault promotion |
| 8 — Process env | Planned | Signals, pipes, cwd, env, PATH, init, devfs, TTY |
| 9 — Virtual memory | Done | `mmap`, page cache, demand paging, W^X |
| 10 — Mount / tmpfs | Done | mount table, tmpfs, rename/symlink |
| 11 — procfs/sysfs | Done | `/proc`, `/sys`; hw snapshot syscalls removed |
| 12 — Preemption | Planned | Involuntary timer preemption (SMP gate) |
| 13 — SMP | Planned | Multicore bring-up, ACPI, SMP-safe kernel |
| 14 — GUI | Planned | Framebuffer, input, minimal window manager |

Full details and recommended order: [docs/roadmap/README.md](docs/roadmap/README.md).

**Phase 5 — completed**

* [x] VirtIO-blk read/write, FAT32 read/write/create/append
* [x] User programs on FAT disk (`/BIN/*`), shell file builtins, `cd`/`pwd`
* [x] VirtIO-net, ARP/IPv4/UDP/ICMP, minimal TCP client
* [x] Socket syscalls; `ip`, `ping`, `dig`, `curl`
* [x] Hardware tools: `lscpu`, `lspci`, `lsblk`, `lsmem` (via `/proc` and `/sys`)

**Deferred**

* [ ] TCP/IP hardening under load (minimal TCP is enough for now)
* [ ] ext2/ext4, btrfs, ZFS (not planned; FAT is the sole on-disk FS)
* [ ] `poll`, `listen`/`accept`, pthreads, dynamic linking — see roadmap deferred backlog

**Phase 6 — next**

* [x] Integration test for `lscpu`; [ ] cover `lspci`, `lsblk`, `lsmem`
* [ ] Expand ABI layout tests; document rebuild-before-QEMU workflow
* [ ] Optional CI: `zig build test` + `mise run test-shell`

## 🔗 Links

* Zig: [https://ziglang.org](https://ziglang.org)
* Limine: [https://github.com/Limine-Bootloader/Limine](https://github.com/Limine-Bootloader/Limine)
* OSDev.org: [https://wiki.osdev.org](https://wiki.osdev.org)
