"""Drive the serial shell in QEMU with prompt-synchronized commands."""

from __future__ import annotations

import pexpect
import subprocess
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class _LogWriter:
    buffer: str = ""

    def write(self, data: str) -> None:
        self.buffer += data

    def flush(self) -> None:
        pass


@dataclass
class QemuShell:
    root: Path
    boot_timeout: float = 90.0
    command_timeout: float = 20.0

    _proc: pexpect.spawn | None = field(default=None, init=False, repr=False)
    _log_writer: _LogWriter = field(default_factory=_LogWriter, init=False, repr=False)

    PROMPT = "os> "
    READY = "Simple shell ready"

    @property
    def log(self) -> str:
        return self._log_writer.buffer

    def start(self) -> None:
        if self._proc is not None:
            raise RuntimeError("session already started")
        self._log_writer = _LogWriter()
        self._proc = pexpect.spawn(
            "sh scripts/run-qemu.sh -display none",
            cwd=str(self.root),
            encoding="utf-8",
            timeout=self.boot_timeout,
            codec_errors="replace",
        )
        self._proc.logfile_read = self._log_writer

    @property
    def proc(self) -> pexpect.spawn:
        if self._proc is None:
            raise RuntimeError("session not started")
        return self._proc

    def wait_ready(self) -> None:
        self.proc.expect(self.READY, timeout=self.boot_timeout)
        self.proc.expect(self.PROMPT, timeout=self.command_timeout)

    def run(self, cmd: str, *, timeout: float | None = None) -> str:
        wait = self.command_timeout if timeout is None else timeout
        self.proc.send(cmd + "\r")
        self.proc.expect(self.PROMPT, timeout=wait)
        return self.proc.before or ""

    def close(self) -> None:
        if self._proc is None:
            return
        try:
            if self._proc.isalive():
                self.proc.send("exit\r")
                try:
                    self.proc.expect(pexpect.EOF, timeout=5)
                except pexpect.TIMEOUT:
                    pass
        finally:
            if self._proc.isalive():
                self._proc.terminate(force=True)
            self._proc.close(force=True)
            self._proc = None
            kill_qemu(self.root)

    def assert_no_faults(self) -> None:
        if "Fault" in self.log:
            raise AssertionError("serial log contains Fault")


def kill_qemu(root: Path) -> None:
    subprocess.run(
        ["pkill", "-f", "qemu-system-x86_64.*os.iso"],
        cwd=root,
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def sync_disk(root: Path) -> None:
    subprocess.run(
        ["uv", "run", "--group", "build", "create-disk"],
        cwd=root,
        check=True,
    )


def assert_contains(window: str, needle: str, case: str) -> None:
    if needle not in window:
        raise AssertionError(
            f"{case}: expected {needle!r} in output window:\n{window}"
        )
