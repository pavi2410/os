"""Resolve Limine host tool and boot file directory."""

from __future__ import annotations

import hashlib
import io
import os
import shutil
import subprocess
import tarfile
import urllib.request
from dataclasses import dataclass
from functools import cache
from pathlib import Path

from scripts.common import REPO_ROOT

LIMINE_VERSION = "v12.3.3"
LIMINE_URL = (
    "https://github.com/Limine-Bootloader/Limine/releases/download/"
    f"{LIMINE_VERSION}/limine-binary.tar.gz"
)
# sha256 of limine-binary.tar.gz for LIMINE_VERSION
LIMINE_SHA256 = "205f98218bb0d5a8ccabf5f903dba9d935f7b0aa66f4262a99b0f5a8e668ec6d"

REQUIRED_SHARE_FILES = (
    "limine-bios.sys",
    "limine-bios-cd.bin",
    "limine-uefi-cd.bin",
    "BOOTX64.EFI",
    "BOOTIA32.EFI",
)


@dataclass(frozen=True)
class LiminePaths:
    bin: Path
    share: Path


def is_valid_limine(bin_path: Path, share_path: Path) -> bool:
    if not bin_path.is_file() or not os.access(bin_path, os.X_OK):
        return False
    return all((share_path / name).is_file() for name in REQUIRED_SHARE_FILES)


@cache
def resolve_limine(root: Path = REPO_ROOT) -> LiminePaths:

    env_bin = os.environ.get("LIMINE_BIN")
    env_share = os.environ.get("LIMINE_SHARE")
    if env_bin and env_share:
        paths = LiminePaths(Path(env_bin), Path(env_share))
        if is_valid_limine(paths.bin, paths.share):
            return paths

    limine_bin = shutil.which("limine")
    if limine_bin:
        prefix = Path(limine_bin).resolve().parent.parent
        paths = LiminePaths(Path(limine_bin), prefix / "share" / "limine")
        if is_valid_limine(paths.bin, paths.share):
            return paths

    brew = shutil.which("brew")
    if brew:
        try:
            brew_prefix = subprocess.run(
                [brew, "--prefix", "limine"],
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
        except subprocess.CalledProcessError:
            brew_prefix = ""
        if brew_prefix:
            paths = LiminePaths(
                Path(brew_prefix) / "bin" / "limine",
                Path(brew_prefix) / "share" / "limine",
            )
            if is_valid_limine(paths.bin, paths.share):
                return paths

    bundled = root / "limine-binary" / "limine"
    if not bundled.is_file() or not os.access(bundled, os.X_OK):
        install_limine_binary(root)

    paths = LiminePaths(bundled, root / "limine-binary")
    if not is_valid_limine(paths.bin, paths.share):
        raise RuntimeError("could not find or install Limine")

    return paths


def bios_install(iso_path: Path) -> None:
    limine = resolve_limine()
    subprocess.run([str(limine.bin), "bios-install", str(iso_path)], check=True)


def install_limine_binary(root: Path) -> None:
    target = root / "limine-binary"
    if target.exists():
        shutil.rmtree(target)

    with urllib.request.urlopen(LIMINE_URL) as response:
        data = response.read()

    digest = hashlib.sha256(data).hexdigest()
    if digest != LIMINE_SHA256:
        raise RuntimeError(
            f"Limine download hash mismatch: got {digest}, expected {LIMINE_SHA256}"
        )

    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        archive.extractall(root, filter="data")

    subprocess.run(["make", "-C", str(target)], check=True)
