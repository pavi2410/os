#!/bin/sh
set -e

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$root"

kernel="$1"
iso="$2"

if [ -z "$kernel" ] || [ -z "$iso" ]; then
    echo "usage: build-iso.sh <kernel-path> <iso-path>" >&2
    exit 1
fi

if [ ! -f "$kernel" ]; then
    echo "error: kernel not found at $kernel" >&2
    exit 1
fi

if ! command -v xorriso >/dev/null 2>&1; then
    echo "error: xorriso not found (macOS: brew install xorriso)" >&2
    exit 1
fi

. "$root/scripts/get-limine.sh"

rm -rf "$root/iso_root"
mkdir -p "$root/iso_root/boot/limine"
mkdir -p "$root/iso_root/EFI/BOOT"

cp "$kernel" "$root/iso_root/boot/kernel"
cp "$root/limine.conf" "$root/iso_root/boot/limine/limine.conf"
cp "$LIMINE_SHARE/limine-bios.sys" "$root/iso_root/boot/limine/"
cp "$LIMINE_SHARE/limine-bios-cd.bin" "$root/iso_root/boot/limine/"
cp "$LIMINE_SHARE/limine-uefi-cd.bin" "$root/iso_root/boot/limine/"
cp "$LIMINE_SHARE/BOOTX64.EFI" "$root/iso_root/EFI/BOOT/"
cp "$LIMINE_SHARE/BOOTIA32.EFI" "$root/iso_root/EFI/BOOT/"

xorriso -as mkisofs -R -r -J -b boot/limine/limine-bios-cd.bin \
    -no-emul-boot -boot-load-size 4 -boot-info-table -hfsplus \
    -apm-block-size 2048 --efi-boot boot/limine/limine-uefi-cd.bin \
    -efi-boot-part --efi-boot-image --protective-msdos-label \
    "$root/iso_root" -o "$iso"

"$LIMINE_BIN" bios-install "$iso"
rm -rf "$root/iso_root"
