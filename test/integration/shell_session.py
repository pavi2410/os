"""Drive the serial shell in QEMU with prompt-synchronized commands."""

from __future__ import annotations

import pexpect
import re
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path

from scripts.qemu import build_qemu_argv, prepare_qmp_socket, qmp_quit, stop_qemu


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
    extra: tuple[str, ...] = ()

    _proc: pexpect.spawn | None = field(default=None, init=False, repr=False)
    _log_writer: _LogWriter = field(default_factory=_LogWriter, init=False, repr=False)

    PROMPT = re.compile(r"/[^\r\n>]*> $", re.MULTILINE)
    READY = "Simple shell ready"

    @property
    def log(self) -> str:
        return self._log_writer.buffer

    def start(self) -> None:
        if self._proc is not None:
            raise RuntimeError("session already started")
        self._log_writer = _LogWriter()
        prepare_qmp_socket()
        argv = build_qemu_argv(display_none=True, extra=self.extra)
        self._proc = pexpect.spawn(
            argv[0],
            argv[1:],
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
        # After COW fork the shell may still be faulting in; brief settle reduces
        # COM1 FIFO overruns (RX is polled, no UART IRQ).
        time.sleep(0.1)
        self.proc.send(cmd + "\r")
        self.proc.expect(self.PROMPT, timeout=wait)
        return self.proc.before or ""

    def send(self, data: str) -> None:
        self.proc.send(data)

    def expect(self, pattern: str | re.Pattern[str], *, timeout: float | None = None) -> str:
        wait = self.command_timeout if timeout is None else timeout
        self.proc.expect(pattern, timeout=wait)
        return self.proc.before or ""

    def expect_prompt(self, *, timeout: float | None = None) -> str:
        return self.expect(self.PROMPT, timeout=timeout)

    def send_ctrl_c(self) -> None:
        self.proc.send("\x03")

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
                qmp_quit()
                if self._proc.isalive():
                    self._proc.terminate(force=True)
            self._proc.close(force=True)
            self._proc = None
            stop_qemu()

    def assert_no_faults(self) -> None:
        if "Fault" in self.log:
            raise AssertionError("serial log contains Fault")


def sync_disk(root: Path) -> None:
    subprocess.run(
        ["uv", "run", "create-disk"],
        cwd=root,
        check=True,
    )


def assert_contains(window: str, needle: str, case: str) -> None:
    if needle not in window:
        raise AssertionError(
            f"{case}: expected {needle!r} in output window:\n{window}"
        )


def output_body(window: str, cmd: str) -> str:
    """Return text after the echoed command line (TTY echo-safe)."""
    text = window.replace("\r", "")
    parts = text.split(cmd, 1)
    if len(parts) < 2:
        raise ValueError(f"command {cmd!r} not found in output window")
    rest = parts[1]
    if rest.startswith("\n"):
        rest = rest[1:]
    return rest


def cat_body(window: str, path: str) -> str:
    return output_body(window, f"cat {path}").rstrip("\n")


def assert_cat_exact(window: str, path: str, expected: str, case: str) -> None:
    try:
        body = cat_body(window, path)
    except ValueError as exc:
        raise AssertionError(f"{case}: {exc}\n{window}") from exc
    if body != expected:
        raise AssertionError(
            f"{case}: expected cat of {path} to be {expected!r}, got {body!r}\n{window}"
        )
