#!/usr/bin/env python3
"""Create or update the FAT32 virtio test disk (README.TXT, /BIN/*).

If zig-out/disk.img already exists, only refresh /README.TXT and /BIN/*.
User-created files at the volume root are preserved across `mise run boot`.
Set OS_DISK_FORCE=1 to reformat from scratch (or run `mise run clean-disk`).
"""

from __future__ import annotations

import datetime
import errno
import logging
import os
from copy import copy
from pathlib import Path

from scripts.common import DISK_PATH, USERSPACE_BIN_DIR
from pyfatfs.DosDateTime import DosDateTime
from pyfatfs.EightDotThree import EightDotThree
from pyfatfs.FATDirectoryEntry import FATDirectoryEntry, make_lfn_entry
from pyfatfs.PyFat import PyFat
from pyfatfs._exceptions import NotAnLFNEntryException, PyFATException

DISK_SIZE = 64 * 1024 * 1024
README_CONTENT = b"Hello from FAT on virtio-blk\r\n"
VOLUME_LABEL = "OSDISK"

logger = logging.getLogger(__name__)


def fat_name(name: str) -> str:
    return name.upper()


def _entry_name(entry: FATDirectoryEntry) -> str:
    try:
        long_name = entry.get_long_name()
    except NotAnLFNEntryException:
        long_name = None
    return (long_name or entry.get_short_name() or "").upper()


def _now() -> datetime.tzinfo:
    return datetime.timezone.utc


def _get_entry(parent: FATDirectoryEntry, name: str) -> FATDirectoryEntry:
    try:
        return parent.get_entry(name)
    except PyFATException as exc:
        if exc.errno == errno.ENOENT:
            raise FileNotFoundError(name) from exc
        raise


def _root_dir(pf: PyFat) -> FATDirectoryEntry:
    root = pf.root_dir
    if root is None:
        raise RuntimeError("FAT filesystem is not open")
    return root


def _write_file(pf: PyFat, path: str, data: bytes) -> None:
    parts = [part for part in path.split("/") if part]
    if not parts:
        raise ValueError(f"invalid path: {path!r}")

    parent = _root_dir(pf)
    for part in parts[:-1]:
        parent = _get_entry(parent, part)
        if not parent.is_directory():
            raise NotADirectoryError(path)

    name = parts[-1]
    try:
        entry = _get_entry(parent, name)
        if entry.is_directory():
            raise IsADirectoryError(path)
        old_cluster = entry.get_cluster()
        if old_cluster:
            pf.free_cluster_chain(old_cluster)
        entry.set_cluster(0)
        entry.filesize = 0
    except FileNotFoundError:
        short = EightDotThree(encoding=pf.encoding)
        short.set_str_name(short.make_8dot3_name(name, parent))
        entry = FATDirectoryEntry.new(name=short, tz=_now(), encoding=pf.encoding)
        short_name = short.get_unpadded_filename()
        if short_name != name.upper():
            entry.set_lfn_entry(make_lfn_entry(name, short))
        parent.add_subdirectory(entry)

    if data:
        cluster = pf.allocate_bytes(len(data))[0]
        entry.set_cluster(cluster)
        pf.write_data_to_cluster(data, cluster)
        entry.filesize = len(data)

    stamp = DosDateTime.now(tz=_now())
    entry.wrttime = stamp.serialize_time()
    entry.wrtdate = stamp.serialize_date()
    entry.lstaccessdate = stamp.serialize_date()
    pf.update_directory_entry(parent)
    pf.flush_fat()


def _ensure_dir(pf: PyFat, path: str) -> FATDirectoryEntry:
    parts = [part for part in path.split("/") if part]
    parent = _root_dir(pf)
    root = parent

    for part in parts:
        try:
            entry = _get_entry(parent, part)
        except FileNotFoundError:
            short = EightDotThree(encoding=pf.encoding)
            short.set_str_name(short.make_8dot3_name(part, parent))
            entry = FATDirectoryEntry.new(
                name=short,
                tz=_now(),
                attr=FATDirectoryEntry.ATTR_DIRECTORY,
                encoding=pf.encoding,
            )
            short_name = short.get_unpadded_filename()
            if short_name != part.upper():
                entry.set_lfn_entry(make_lfn_entry(part, short))

            first_cluster = pf.allocate_bytes(
                FATDirectoryEntry.FAT_DIRECTORY_HEADER_SIZE * 2,
                erase=True,
            )[0]
            entry.set_cluster(first_cluster)

            dot_short = EightDotThree()
            dot_short.set_byte_name(b".          ")
            dot = FATDirectoryEntry.new(
                name=dot_short,
                tz=_now(),
                attr=FATDirectoryEntry.ATTR_DIRECTORY,
                encoding=pf.encoding,
            )
            dot.set_cluster(first_cluster)

            dotdot_short = EightDotThree()
            dotdot_short.set_byte_name(b"..         ")
            dotdot = copy(parent)
            dotdot.name = dotdot_short
            dotdot.lfn_entry = None
            if parent == root:
                dotdot.set_cluster(0)

            entry.add_subdirectory(dot)
            entry.add_subdirectory(dotdot)
            pf.update_directory_entry(entry)

            parent.add_subdirectory(entry)
            pf.update_directory_entry(parent)
            pf.flush_fat()
        else:
            if not entry.is_directory():
                raise NotADirectoryError(path)

        parent = entry

    return parent


def format_disk(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\0" * DISK_SIZE)
    pf = PyFat()
    pf.mkfs(
        str(path),
        PyFat.FAT_TYPE_FAT32,
        size=DISK_SIZE,
        label=VOLUME_LABEL,
    )
    pf.close()


def sync_disk(path: Path, readme: bytes, user_bins: dict[str, Path]) -> None:
    pf = PyFat()
    pf.open(str(path), read_only=False)
    try:
        _write_file(pf, "/README.TXT", readme)
        bin_dir = _ensure_dir(pf, "/BIN")
        desired = {name.upper() for name in user_bins}
        # get_entries() returns (dirs, files, specials), not a flat iterator.
        _dirs, files, _specials = bin_dir.get_entries()
        for entry in list(files):
            name = _entry_name(entry)
            if not name or name in desired:
                continue
            cluster = entry.get_cluster()
            if cluster:
                pf.free_cluster_chain(cluster)
            bin_dir.remove_dir_entry(entry.get_short_name())
            logger.info("disk: removed stale /BIN/%s", name)
        pf.update_directory_entry(bin_dir)
        pf.flush_fat()
        for dest_name, src in user_bins.items():
            _write_file(pf, f"/BIN/{dest_name}", src.read_bytes())
    finally:
        pf.close()


def collect_user_bins() -> dict[str, Path]:
    if not USERSPACE_BIN_DIR.is_dir():
        logger.error("%s not found (run: mise run build)", USERSPACE_BIN_DIR)
        raise SystemExit(1)

    bins: dict[str, Path] = {}
    for src in sorted(USERSPACE_BIN_DIR.iterdir()):
        if src.is_file():
            bins[fat_name(src.name)] = src

    if not bins:
        logger.error("no user binaries in %s", USERSPACE_BIN_DIR)
        raise SystemExit(1)

    return bins


def create_disk() -> None:
    force = os.environ.get("OS_DISK_FORCE", "0") == "1"
    user_bins = collect_user_bins()

    if DISK_PATH.is_file() and not force:
        logger.info("disk: updating %s (existing files preserved)", DISK_PATH)
        sync_disk(DISK_PATH, README_CONTENT, user_bins)
    else:
        logger.info("disk: creating %s", DISK_PATH)
        format_disk(DISK_PATH)
        sync_disk(DISK_PATH, README_CONTENT, user_bins)


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    create_disk()


if __name__ == "__main__":
    main()
