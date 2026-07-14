#!/usr/bin/env python3
"""Summarize PC/PK post-synthesis timing and utilization reports."""

from __future__ import annotations

import argparse
import csv
import re
from dataclasses import dataclass
from pathlib import Path


CONFIG_RE = re.compile(r"pc(?P<pc>\d+)_pk(?P<pk>\d+)$")


@dataclass
class Result:
    pc: int
    pk: int
    period_ns: float
    wns_ns: float
    luts: int
    registers: int
    bram_tiles: float
    dsps: int

    @property
    def timing_met(self) -> bool:
        return self.wns_ns >= 0.0

    @property
    def critical_delay_ns(self) -> float:
        return self.period_ns - self.wns_ns

    @property
    def estimated_fmax_mhz(self) -> float:
        return 1000.0 / self.critical_delay_ns

    @property
    def macs_per_cycle(self) -> int:
        return self.pc * self.pk

    @property
    def peak_gmac_s(self) -> float:
        return self.macs_per_cycle * (1000.0 / self.period_ns) / 1000.0


def parse_metadata(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text().splitlines():
        key, value = line.split("=", 1)
        values[key] = value
    return values


def parse_number(value: str) -> float:
    return float(value.replace(",", ""))


def parse_utilization(path: Path) -> dict[str, float]:
    wanted = {
        "Slice LUTs": "luts",
        "Slice Registers": "registers",
        "Block RAM Tile": "bram_tiles",
        "DSPs": "dsps",
    }
    values: dict[str, float] = {}

    for line in path.read_text(errors="replace").splitlines():
        columns = [column.strip() for column in line.strip().strip("|").split("|")]
        if not columns:
            continue
        label = columns[0].rstrip("*")
        if label in wanted and len(columns) >= 2:
            values[wanted[label]] = parse_number(columns[1])
    return values


def load_result(config_dir: Path) -> Result:
    match = CONFIG_RE.match(config_dir.name)
    if not match:
        raise ValueError(f"Unexpected configuration directory: {config_dir}")

    metadata = parse_metadata(config_dir / "metadata.txt")
    utilization = parse_utilization(config_dir / "utilization.rpt")
    return Result(
        pc=int(metadata["pc"]),
        pk=int(metadata["pk"]),
        period_ns=float(metadata["clock_period_ns"]),
        wns_ns=float(metadata["wns_ns"]),
        luts=int(utilization["luts"]),
        registers=int(utilization["registers"]),
        bram_tiles=utilization["bram_tiles"],
        dsps=int(utilization["dsps"]),
    )


def render_markdown(results: list[Result]) -> str:
    timing_candidates = [result for result in results if result.timing_met]
    recommendation = max(
        timing_candidates,
        key=lambda result: (result.macs_per_cycle, result.estimated_fmax_mhz),
        default=None,
    )

    lines = [
        "# PC/PK Synthesis Experiments",
        "",
        "Target: Digilent Zybo Z7-20 (`xc7z020clg400-1`) at 125 MHz.",
        "",
        "These are out-of-context post-synthesis estimates for the parallel "
        "compute slice: MAC array, partial-sum accumulator, and parallel "
        "post-processing. They are not full-accelerator or post-route measurements.",
        "",
        "| PC | PK | MACs/cycle | Peak GMAC/s at 125 MHz | WNS (ns) | Est. Fmax (MHz) | LUTs | Registers | BRAM tiles | DSPs | Timing |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|",
    ]

    for result in results:
        lines.append(
            f"| {result.pc} | {result.pk} | {result.macs_per_cycle} | "
            f"{result.peak_gmac_s:.3f} | {result.wns_ns:.3f} | "
            f"{result.estimated_fmax_mhz:.1f} | {result.luts:,} | "
            f"{result.registers:,} | {result.bram_tiles:g} | {result.dsps:,} | "
            f"{'Met' if result.timing_met else 'Failed'} |"
        )

    lines.extend(["", "## Interpretation", ""])
    if recommendation:
        lines.append(
            f"`PC={recommendation.pc}, PK={recommendation.pk}` is the recommended "
            f"baseline among timing-clean configurations because it provides "
            f"{recommendation.macs_per_cycle} MACs/cycle at an estimated "
            f"{recommendation.estimated_fmax_mhz:.1f} MHz post-synthesis Fmax."
        )
    else:
        lines.append(
            "No swept configuration met the 125 MHz post-synthesis target. "
            "Pipeline or memory-path work is required before implementation."
        )

    lines.extend(
        [
            "",
            "The full AXI top remains dominated by simulation-oriented tensor "
            "register arrays, so these results intentionally isolate the hardware "
            "that `PC/PK` changes. Vivado maps the current signed INT8 multipliers "
            "into LUT fabric in this isolated design, which explains the zero DSP "
            "count. Before carrying this baseline into the board-facing design, "
            "run the full regression and confirm post-route timing in the "
            "dedicated block design.",
            "",
            "Regenerate:",
            "",
            "```bash",
            "make synth-sweep",
            "```",
            "",
        ]
    )
    return "\n".join(lines)


def write_csv(path: Path, results: list[Result]) -> None:
    with path.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "pc",
                "pk",
                "macs_per_cycle",
                "peak_gmac_s_125mhz",
                "wns_ns",
                "estimated_fmax_mhz",
                "luts",
                "registers",
                "bram_tiles",
                "dsps",
                "timing_met",
            ]
        )
        for result in results:
            writer.writerow(
                [
                    result.pc,
                    result.pk,
                    result.macs_per_cycle,
                    f"{result.peak_gmac_s:.3f}",
                    f"{result.wns_ns:.3f}",
                    f"{result.estimated_fmax_mhz:.1f}",
                    result.luts,
                    result.registers,
                    f"{result.bram_tiles:g}",
                    result.dsps,
                    result.timing_met,
                ]
            )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sweep-root", type=Path, required=True)
    parser.add_argument("--markdown", type=Path, required=True)
    args = parser.parse_args()

    config_dirs = sorted(
        path
        for path in args.sweep_root.iterdir()
        if path.is_dir() and CONFIG_RE.match(path.name)
    )
    results = [load_result(path) for path in config_dirs]
    if not results:
        raise SystemExit(f"No synthesis results found under {args.sweep_root}")

    args.markdown.parent.mkdir(parents=True, exist_ok=True)
    args.markdown.write_text(render_markdown(results))
    write_csv(args.sweep_root / "summary.csv", results)

    print(args.markdown.read_text())
    print(f"Wrote {args.markdown}")
    print(f"Wrote {args.sweep_root / 'summary.csv'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
