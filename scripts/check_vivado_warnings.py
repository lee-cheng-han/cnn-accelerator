#!/usr/bin/env python3
"""Check Vivado logs against a small, explicit warning budget."""

from __future__ import annotations

import re
import sys
from collections import Counter
from pathlib import Path


REQUIRED_LOGS = [
    Path("build/arty_z7_20_cnn/arty_z7_20_cnn.runs/synth_1/runme.log"),
    Path("build/arty_z7_20_cnn/arty_z7_20_cnn.runs/impl_1/runme.log"),
]
OPTIONAL_LOGS = [
    Path("vivado.log"),
]

KNOWN_WARNINGS = [
    ("Board store entries for unavailable installed parts", re.compile(r"\[Board 49-26\] cannot add Board Part")),
    ("Board automation queried without installed board metadata", re.compile(r"\[Boardtcl 53-1\] No current board_part set")),
    ("Project created by part when board metadata is absent", re.compile(r"\[Project 1-5713\] Board part '' set")),
    ("Generated AXI interconnect ID-width adaptation", re.compile(r"\[BD 41-2384\] Width mismatch when connecting pin:")),
    ("Optional System ILA monitor direction default", re.compile(r"\[BD 5-1069\] Please specify '-mon_dir' argument")),
    ("Regenerated BD/IP constraint overwrite", re.compile(r"\[IP_Flow 19-4994\] Overwriting existing constraint file")),
    ("Fresh run without incremental checkpoint", re.compile(r"\[Vivado 12-7122\] Auto Incremental Compile")),
    ("Optional generated IP port left unconnected", re.compile(r"\[Synth 8-7071\] port '.+' of module '.+' is unconnected")),
    ("Generated wrapper omits optional IP ports", re.compile(r"\[Synth 8-7023\] instance '.+' of module '.+' has \d+ connections declared")),
    ("Generated interconnect port-width adaptation", re.compile(r"\[Synth 8-689\] width \(\d+\) of port connection '.+' does not match")),
    ("Generated interconnect clock/reset or ID bits trimmed", re.compile(r"\[Synth 8-7129\] Port .+ is either unconnected or has no load")),
    ("Vectorless power estimate reset activity warning", re.compile(r"\[Power 33-332\] Found switching activity")),
]


def classify_warning(line: str) -> str | None:
    for name, pattern in KNOWN_WARNINGS:
        if pattern.search(line):
            return name
    return None


def main() -> int:
    missing = [path for path in REQUIRED_LOGS if not path.exists()]
    if missing:
        print("Missing log files:")
        for path in missing:
            print(f"  {path}")
        print("Run `make arty-z7-bitstream` first, then rerun this check.")
        return 2

    logs = REQUIRED_LOGS + [path for path in OPTIONAL_LOGS if path.exists()]

    errors: list[tuple[Path, int, str]] = []
    criticals: list[tuple[Path, int, str]] = []
    unknown: list[tuple[Path, int, str]] = []
    known_counts: Counter[str] = Counter()
    warning_count = 0

    for path in logs:
        for lineno, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
            if line.startswith("ERROR:"):
                errors.append((path, lineno, line))
            elif line.startswith("CRITICAL WARNING:"):
                criticals.append((path, lineno, line))
            elif line.startswith("WARNING:"):
                warning_count += 1
                category = classify_warning(line)
                if category is None:
                    unknown.append((path, lineno, line))
                else:
                    known_counts[category] += 1

    print("Vivado warning budget")
    print("=====================")
    print(f"Logs checked: {len(logs)}")
    print(f"Warnings: {warning_count}")
    print(f"Known warnings: {sum(known_counts.values())}")
    print(f"Unknown warnings: {len(unknown)}")
    print(f"Critical warnings: {len(criticals)}")
    print(f"Errors: {len(errors)}")

    if known_counts:
        print("")
        print("Known warning categories:")
        for category, count in known_counts.most_common():
            print(f"  {count:4d}  {category}")

    if errors or criticals or unknown:
        print("")
        print("Unexpected log entries:")
        for path, lineno, line in errors + criticals + unknown[:20]:
            print(f"  {path}:{lineno}: {line}")
        if len(unknown) > 20:
            print(f"  ... {len(unknown) - 20} more unknown warnings")
        return 1

    print("")
    print("PASS: no errors, no critical warnings, and no warnings outside docs/known_warnings.md.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
