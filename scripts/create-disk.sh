#!/bin/sh
# Create a FAT32 virtio disk image with README.TXT and user programs under /BIN.
# macOS: hdiutil + newfs_msdos (built-in). Linux: mkfs.vfat + loop mount.
set -e

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
disk="$root/zig-out/disk.img"
bin_dir="$root/zig-out/userspace/bin"
readme="$(mktemp)"
printf 'Hello from FAT on virtio-blk\r\n' >"$readme"
trap 'rm -f "$readme"' EXIT

if [ ! -d "$bin_dir" ]; then
    echo "error: $bin_dir not found (run: mise run build)" >&2
    exit 1
fi

user_bins=""
for bin in "$bin_dir"/*; do
    [ -f "$bin" ] || continue
    user_bins="$user_bins $bin"
done

if [ -z "$user_bins" ]; then
    echo "error: no user binaries in $bin_dir (run: mise run build)" >&2
    exit 1
fi

fat_name() {
    printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

mkdir -p "$(dirname "$disk")"
dd if=/dev/zero of="$disk" bs=1M count=64 status=none 2>/dev/null

copy_disk_files() {
    target="$1"
    # Prevent macOS AppleDouble (._*) sidecars when copying onto FAT.
    COPYFILE_DISABLE=1 cp "$readme" "$target/README.TXT"
    mkdir "$target/BIN"
    for bin in $user_bins; do
        base=$(basename "$bin")
        COPYFILE_DISABLE=1 cp "$bin" "$target/BIN/$(fat_name "$base")"
    done
}

clean_macos_junk() {
    target="$1"
    rm -rf "$target/.fseventsd" "$target/.DS_Store" "$target/.Spotlight-V100" "$target/.Trashes" 2>/dev/null || true
    rm -f "$target"/._* 2>/dev/null || true
    rm -f "$target"/*/._* 2>/dev/null || true
}

format_macos() {
    dev="$(hdiutil attach -nomount "$disk" | awk 'END {print $1}')"
    newfs_msdos -F 32 -v OSDISK "$dev" >/dev/null
    hdiutil detach "$dev" >/dev/null

    # Re-attach so macOS mounts the FAT volume.
    line="$(hdiutil attach "$disk" | awk 'END {print $0}')"
    dev="$(printf '%s\n' "$line" | awk '{print $1}')"
    mnt="$(printf '%s\n' "$line" | awk '{print $NF}')"
    copy_disk_files "$mnt"
    clean_macos_junk "$mnt"
    hdiutil detach "$dev" >/dev/null
}

format_linux() {
    mkfs.vfat -F 32 -S 512 -s 1 -n OSDISK "$disk" >/dev/null
    mnt="$(mktemp -d)"
    mount -o loop "$disk" "$mnt"
    copy_disk_files "$mnt"
    umount "$mnt"
    rmdir "$mnt"
}

format_mtools() {
    mformat -i "$disk" -F -v OSDISK -s 131072 -h 64 -S 512 -c 8 :: >/dev/null
    mcopy -i "$disk" "$readme" ::/README.TXT
    mmd -i "$disk" ::/BIN
    for bin in $user_bins; do
        base=$(basename "$bin")
        mcopy -i "$disk" "$bin" "::/BIN/$(fat_name "$base")"
    done
}

case "$(uname -s)" in
    Darwin)
        if command -v mformat >/dev/null 2>&1 && command -v mcopy >/dev/null 2>&1; then
            format_mtools
        elif command -v newfs_msdos >/dev/null 2>&1; then
            format_macos
        else
            echo "error: need mtools or newfs_msdos on macOS" >&2
            exit 1
        fi
        ;;
    Linux)
        if command -v mkfs.vfat >/dev/null 2>&1; then
            format_linux
        elif command -v mformat >/dev/null 2>&1; then
            format_mtools
        else
            echo "error: need mkfs.vfat or mtools on Linux" >&2
            exit 1
        fi
        ;;
    *)
        if command -v mformat >/dev/null 2>&1; then
            format_mtools
        else
            echo "error: unsupported OS; install mtools or run on macOS/Linux" >&2
            exit 1
        fi
        ;;
esac
