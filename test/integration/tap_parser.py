"""Parse TAP 13 output from mixed serial logs."""

from __future__ import annotations

import re
from dataclasses import dataclass, field

_TAP_VERSION = re.compile(r"^TAP version 13\s*$")
_PLAN = re.compile(r"^1\.\.(\d+)\s*$")
_OK = re.compile(r"^ok(?: (\d+))? - (.+)$")
_NOT_OK = re.compile(r"^not ok(?: (\d+))? - (.+)$")
_BAIL = re.compile(r"^Bail out!(?: (.*))?$")


@dataclass
class TapCase:
    number: int | None
    name: str
    passed: bool
    diagnostics: list[str] = field(default_factory=list)


@dataclass
class TapReport:
    cases: list[TapCase] = field(default_factory=list)
    planned: int | None = None
    bail: str | None = None

    @property
    def passed(self) -> int:
        return sum(1 for case in self.cases if case.passed)

    @property
    def failed(self) -> int:
        return sum(1 for case in self.cases if not case.passed)

    def assert_all_passed(self, label: str) -> None:
        if self.bail is not None:
            raise AssertionError(f"{label}: bail out: {self.bail}")
        if self.planned is None:
            raise AssertionError(f"{label}: missing TAP plan")
        if len(self.cases) == 0:
            raise AssertionError(f"{label}: no TAP test results")
        failures = [case for case in self.cases if not case.passed]
        if failures:
            lines = [f"  not ok - {case.name}" for case in failures]
            if failures[0].diagnostics:
                lines.extend(f"    {line}" for line in failures[0].diagnostics)
            raise AssertionError(
                f"{label}: {len(failures)} failed, {self.passed} passed\n"
                + "\n".join(lines)
            )
        if self.planned != len(self.cases):
            raise AssertionError(
                f"{label}: planned {self.planned} tests, got {len(self.cases)} results"
            )


def _normalize(text: str) -> list[str]:
    text = text.replace("\r", "")
    return text.split("\n")


def parse_tap(text: str) -> TapReport:
    report = TapReport()
    current: TapCase | None = None

    for raw in _normalize(text):
        line = raw.rstrip()
        if not line or line.startswith("#"):
            continue

        if _TAP_VERSION.match(line):
            continue

        bail = _BAIL.match(line)
        if bail:
            report.bail = bail.group(1) or "unknown"
            break

        plan = _PLAN.match(line)
        if plan:
            report.planned = int(plan.group(1))
            continue

        ok = _OK.match(line)
        if ok:
            if current is not None:
                report.cases.append(current)
            current = TapCase(
                number=int(ok.group(1)) if ok.group(1) else None,
                name=ok.group(2),
                passed=True,
            )
            continue

        not_ok = _NOT_OK.match(line)
        if not_ok:
            if current is not None:
                report.cases.append(current)
            current = TapCase(
                number=int(not_ok.group(1)) if not_ok.group(1) else None,
                name=not_ok.group(2),
                passed=False,
            )
            continue

        if current is not None and (line == "  ---" or line == "  ..."):
            continue
        if current is not None and line.startswith("  "):
            current.diagnostics.append(line[2:])

    if current is not None:
        report.cases.append(current)

    return report


def extract_between(text: str, start: str, end: str) -> str:
    begin = text.find(start)
    if begin < 0:
        raise AssertionError(f"missing marker {start!r}")
    begin += len(start)
    stop = text.find(end, begin)
    if stop < 0:
        raise AssertionError(f"missing marker {end!r}")
    return text[begin:stop]
