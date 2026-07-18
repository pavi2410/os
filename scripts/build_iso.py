#!/usr/bin/env python3
"""Build a bootable Limine ISO from the kernel ELF."""

from __future__ import annotations

import logging
import shutil
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

import pycdlib
from pycdlib import utils as pycdlib_utils

from scripts.common import ISO_PATH, KERNEL_PATH, REPO_ROOT
from scripts.limine import bios_install, resolve_limine

INTERCHANGE_LEVEL = 3

BIOS_BOOT_IMAGE = PurePosixPath("boot/limine/limine-bios-cd.bin")
UEFI_BOOT_IMAGE = PurePosixPath("boot/limine/limine-uefi-cd.bin")

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class IsoFile:
    dest: Path
    source: Path


def iso_root_files() -> tuple[IsoFile, ...]:
    limine_share = resolve_limine().share
    return (
        IsoFile(Path("boot/kernel"), KERNEL_PATH),
        IsoFile(Path("boot/limine/limine.conf"), REPO_ROOT / "limine.conf"),
        IsoFile(Path("boot/limine/limine-bios.sys"), limine_share / "limine-bios.sys"),
        IsoFile(Path("boot/limine/limine-bios-cd.bin"), limine_share / "limine-bios-cd.bin"),
        IsoFile(Path("boot/limine/limine-uefi-cd.bin"), limine_share / "limine-uefi-cd.bin"),
        IsoFile(Path("EFI/BOOT/BOOTX64.EFI"), limine_share / "BOOTX64.EFI"),
        IsoFile(Path("EFI/BOOT/BOOTIA32.EFI"), limine_share / "BOOTIA32.EFI"),
    )


def iso9660_dir_name(name: str) -> str:
    return pycdlib_utils.mangle_dir_for_iso9660(name, INTERCHANGE_LEVEL)


def iso9660_file_name(name: str) -> str:
    base, ext = pycdlib_utils.mangle_file_for_iso9660(name, INTERCHANGE_LEVEL)
    if ext == ";1":
        return f"{base};1"
    return f"{base}.{ext}"


def iso9660_dir_path(relative: PurePosixPath) -> str:
    return "/" + "/".join(iso9660_dir_name(part) for part in relative.parts)


def iso9660_file_path(relative: PurePosixPath) -> str:
    iso_dirs = [iso9660_dir_name(part) for part in relative.parts[:-1]]
    iso_file = iso9660_file_name(relative.parts[-1])
    return "/" + "/".join([*iso_dirs, iso_file])


def joliet_path(relative: PurePosixPath) -> str:
    return "/" + relative.as_posix()


def stage_iso_root() -> Path:
    iso_root = REPO_ROOT / "iso_root"
    if iso_root.exists():
        shutil.rmtree(iso_root)

    for entry in iso_root_files():
        dest_path = iso_root / entry.dest
        dest_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(entry.source, dest_path)

    return iso_root


def populate_iso(iso: pycdlib.PyCdlib, iso_root: Path) -> None:
    dirs: set[PurePosixPath] = set()
    files: list[tuple[Path, PurePosixPath]] = []

    for path in sorted(iso_root.rglob("*")):
        relative = PurePosixPath(path.relative_to(iso_root).as_posix())
        if path.is_dir():
            dirs.add(relative)
            continue
        files.append((path, relative))
        for parent in relative.parents:
            if str(parent) != ".":
                dirs.add(parent)

    for relative in sorted(dirs, key=lambda path: (len(path.parts), path.as_posix())):
        iso.add_directory(
            iso9660_dir_path(relative),
            rr_name=relative.name,
            joliet_path=joliet_path(relative),
        )

    for host_path, relative in files:
        iso.add_file(
            str(host_path),
            iso9660_file_path(relative),
            rr_name=relative.name,
            joliet_path=joliet_path(relative),
        )


def write_iso(iso_root: Path, iso_path: Path) -> None:
    iso = pycdlib.PyCdlib()
    iso.new(interchange_level=INTERCHANGE_LEVEL, rock_ridge="1.09", joliet=3)
    populate_iso(iso, iso_root)

    bios_boot = iso9660_file_path(BIOS_BOOT_IMAGE)
    uefi_boot = iso9660_file_path(UEFI_BOOT_IMAGE)
    iso.add_eltorito(bios_boot, boot_load_size=4, boot_info_table=True)
    iso.add_eltorito(uefi_boot, platform_id=0xEF, efi=True)

    iso.write(str(iso_path))
    iso.close()


def build_iso() -> None:
    if not KERNEL_PATH.is_file():
        logger.error("kernel not found at %s", KERNEL_PATH)
        raise SystemExit(1)

    iso_root = stage_iso_root()
    try:
        ISO_PATH.parent.mkdir(parents=True, exist_ok=True)
        # Write to a temp path, bios-install, then rename so a failed install
        # cannot leave a cached half-finished zig-out/os.iso for mise.
        tmp_iso = ISO_PATH.with_name(ISO_PATH.name + ".tmp")
        if tmp_iso.exists():
            tmp_iso.unlink()
        try:
            write_iso(iso_root, tmp_iso)
            bios_install(tmp_iso)
            tmp_iso.replace(ISO_PATH)
        except BaseException:
            if tmp_iso.exists():
                tmp_iso.unlink()
            raise
    finally:
        shutil.rmtree(iso_root, ignore_errors=True)


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    build_iso()


if __name__ == "__main__":
    main()
