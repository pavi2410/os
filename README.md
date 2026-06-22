# os

**A hobby operating system** in Zig, targeting x86-64 with UEFI, aiming for Linux ABI compatibility, multicore support, filesystems, networking, and eventually a GUI.

## 🚀 Goals

* x86-64 architecture
* UEFI bootloader
* Modern 64-bit kernel
* Linux-compatible syscall interface
* Multicore threading (SMP)
* ext2 or FAT32 filesystem
* BSD-style sockets and TCP/IP networking
* Simple terminal with ANSI parsing
* GUI with basic window manager (future)
* Written in Zig for safety, simplicity, and modern tooling

## 🛠 Toolchain

* Zig (v0.16+ recommended)
* QEMU — `qemu-system-x86_64`
* OVMF (UEFI firmware for QEMU)

### macOS

Install [Homebrew](https://brew.sh) and [mise](https://mise.jdx.dev), then:

```bash
brew install qemu
mise install
eval "$(mise activate zsh)"   # add to ~/.zshrc to persist
```

Copy UEFI firmware into the project (one-time):

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

Copy UEFI firmware into the project (one-time):

```bash
mkdir -p ovmf
cp /usr/share/OVMF/OVMF_CODE_4M.fd ovmf/
cp /usr/share/OVMF/OVMF_VARS_4M.fd ovmf/
```

## 💻 Building & Running

To build the project:

```bash
zig build
```

To build **and** run it automatically in QEMU:

```bash
zig build run
```

*This uses the `build.zig` configuration to launch QEMU and pass the kernel `.efi` automatically.*

## 📝 Roadmap

* [x] Hello UEFI kernel in Zig
* [ ] Page tables and higher-half kernel
* [ ] Memory allocator (physical/virtual)
* [ ] ELF loader for user programs
* [ ] Initial Linux-compatible syscalls
* [ ] Filesystem driver (ext2 or FAT32)
* [ ] Network driver (virtio-net or e1000)
* [ ] Simple TCP/IP stack
* [ ] Terminal + TTY driver
* [ ] Shell + user programs
* [ ] SMP multicore support
* [ ] GUI with framebuffer / window manager

## 🔗 Links

* Zig: [https://ziglang.org](https://ziglang.org)
* OSDev.org: [https://wiki.osdev.org](https://wiki.osdev.org)
