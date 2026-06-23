#!/bin/sh
# Resolve Limine host tool and boot file directory.
# Exports LIMINE_BIN and LIMINE_SHARE for use by build-iso.sh.
#
# Resolution order:
#   1. LIMINE_BIN + LIMINE_SHARE (if already set and valid)
#   2. limine on PATH with share/limine next to its install prefix
#   3. Homebrew: $(brew --prefix limine)/{bin,share/limine}
#   4. Download limine-binary v12.3.3 into the project tree

set -e

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"

limine_version="v12.3.3"
limine_url="https://github.com/Limine-Bootloader/Limine/releases/download/${limine_version}/limine-binary.tar.gz"

try_set() {
    bin="$1"
    share="$2"

    if [ -x "$bin" ] && [ -f "$share/limine-bios.sys" ] && [ -f "$share/limine-bios-cd.bin" ]; then
        LIMINE_BIN="$bin"
        LIMINE_SHARE="$share"
        export LIMINE_BIN LIMINE_SHARE
        return 0
    fi
    return 1
}

if try_set "${LIMINE_BIN}" "${LIMINE_SHARE}"; then
    exit 0
fi

if command -v limine >/dev/null 2>&1; then
    limine_bin=$(command -v limine)
    prefix=$(CDPATH= cd -- "$(dirname "$limine_bin")/.." && pwd)
    if try_set "$limine_bin" "$prefix/share/limine"; then
        exit 0
    fi
fi

if command -v brew >/dev/null 2>&1; then
    brew_prefix=$(brew --prefix limine 2>/dev/null || true)
    if [ -n "$brew_prefix" ]; then
        if try_set "$brew_prefix/bin/limine" "$brew_prefix/share/limine"; then
            exit 0
        fi
    fi
fi

if [ ! -x "$root/limine-binary/limine" ]; then
    rm -rf "$root/limine-binary"
    curl -fsSL "$limine_url" | tar xz -C "$root"
    make -C "$root/limine-binary"
fi

try_set "$root/limine-binary/limine" "$root/limine-binary" || {
    echo "error: could not find or install Limine" >&2
    exit 1
}
