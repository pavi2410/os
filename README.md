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

* Zig (v0.14+ recommended)
* QEMU - `qemu-system-x86_64`
* OVMF (UEFI firmware for QEMU) - `/usr/share/ovmf/OVMF.fd`
* WSL / Linux (build environment)

Run the following command to install the required tools:

```bash
sudo apt install qemu-system-x86
mise activate
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
