#!/bin/sh
# Create or update the FAT32 virtio disk image (README.TXT, /BIN/*).
#
# If zig-out/disk.img already exists, only refresh /BIN (and README.TXT).
# User-created files at the volume root are preserved across `mise run boot`.
# Set OS_DISK_FORCE=1 or run `mise run clean-disk` to reformat from scratch.
#
# macOS: mtools (preferred) or hdiutil + newfs_msdos. Linux: mkfs.vfat + mount.
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

copy_disk_files() {
    target="$1"
    COPYFILE_DISABLE=1 cp "$readme" "$target/README.TXT"
    mkdir -p "$target/BIN"
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

sync_mtools() {
    mcopy -o -i "$disk" "$readme" ::/README.TXT
    mmd -i "$disk" ::/BIN 2>/dev/null || true
    for bin in $user_bins; do
        base=$(basename "$bin")
        mcopy -o -i "$disk" "$bin" "::/BIN/$(fat_name "$base")"
    done
}

sync_macos() {
    line="$(hdiutil attach "$disk" | awk 'END {print $0}')"
    dev="$(printf '%s\n' "$line" | awk '{print $1}')"
    mnt="$(printf '%s\n' "$line" | awk '{print $NF}')"
    copy_disk_files "$mnt"
    clean_macos_junk "$mnt"
    hdiutil detach "$dev" >/dev/null
}

sync_linux() {
    mnt="$(mktemp -d)"
    mount -o loop "$disk" "$mnt"
    copy_disk_files "$mnt"
    umount "$mnt"
    rmdir "$mnt"
}

run_sync() {
    case "$(uname -s)" in
        Darwin)
            if command -v mformat >/dev/null 2>&1 && command -v mcopy >/dev/null 2>&1; then
                sync_mtools
            else
                sync_macos
            fi
            ;;
        Linux)
            if command -v mount >/dev/null 2>&1; then
                sync_linux
            elif command -v mcopy >/dev/null 2>&1; then
                sync_mtools
            else
                echo "error: need mount or mtools to update disk" >&2
                exit 1
            fi
            ;;
        *)
            if command -v mcopy >/dev/null 2>&1; then
                sync_mtools
            else
                echo "error: need mtools to update disk on this OS" >&2
                exit 1
            fi
            ;;
    esac
}

format_macos() {
    dev="$(hdiutil attach -nomount "$disk" | awk 'END {print $1}')"
    newfs_msdos -F 32 -v OSDISK "$dev" >/dev/null
    hdiutil detach "$dev" >/dev/null

    line="$(hdiutil attach "$disk" | awk 'END {print $0}')"
    dev="$(printf '%s\n' "$line" | awk '{print $1}')"
    mnt="$(printf '%s\n' "$line" | awk '{print $NF}')"
    copy_disk_files "$mnt"
    clean_macos_junk "$mnt"
    hdiutil detach "$dev" >/dev/null
}

format_linux() {
    mkfs.vfat -F 32 -S 512 -s 1 -n OSDISK "$disk" >/dev/null
    sync_linux
}

format_mtools() {
    mformat -i "$disk" -F -v OSDISK -s 131072 -h 64 -S 512 -c 8 :: >/dev/null
    sync_mtools
}

run_format() {
    mkdir -p "$(dirname "$disk")"
    dd if=/dev/zero of="$disk" bs=1M count=64 status=none 2>/dev/null

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
}

if [ -f "$disk" ] && [ "${OS_DISK_FORCE:-0}" != 1 ]; then
    echo "disk: updating $disk (existing files preserved)"
    run_sync
else
    echo "disk: creating $disk"
    run_format
fi
