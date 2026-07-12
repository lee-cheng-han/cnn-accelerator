#!/usr/bin/env python3
"""Summarize the  top-level out-of-context implementation experiment."""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path


UTIL_LABELS = {
    "Slice LUTs": "luts",
    "Slice Registers": "registers",
    "F7 Muxes": "f7_muxes",
    "F8 Muxes": "f8_muxes",
    "Block RAM Tile": "bram_tiles",
    "DSPs": "dsps",
}


@dataclass
class TopImplResult:
    part: str
    top: str
    pc: int
    pk: int
    max_cin: int
    max_cout: int
    max_pixels: int
    period_ns: float
    wns_ns: float | None
    whs_ns: float | None
    result_stage: str
    implementation_status: str
    implementation_error_file: str | None
    luts: int
    registers: int
    f7_muxes: int
    f8_muxes: int
    bram_tiles: float
    dsps: int

    @property
    def setup_met(self) -> bool:
        return self.wns_ns is not None and self.wns_ns >= 0.0

    @property
    def hold_met(self) -> bool:
        return self.whs_ns is not None and self.whs_ns >= 0.0

    @property
    def timing_met(self) -> bool:
        return self.setup_met and self.hold_met

    @property
    def critical_delay_ns(self) -> float:
        if self.wns_ns is None:
            return self.period_ns
        return self.period_ns - self.wns_ns

    @property
    def estimated_fmax_mhz(self) -> float:
        return 1000.0 / self.critical_delay_ns


def parse_metadata(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text().splitlines():
        if not line or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value
    return values


def parse_number(value: str) -> float:
    return float(value.replace(",", ""))


def parse_optional_float(value: str) -> float | None:
    if value.upper() == "NA":
        return None
    return float(value)


def parse_utilization(path: Path) -> dict[str, float]:
    values: dict[str, float] = {}
    for line in path.read_text(errors="replace").splitlines():
        columns = [column.strip() for column in line.strip().strip("|").split("|")]
        if not columns:
            continue
        label = re.sub(r"\s+\*", "", columns[0]).rstrip("*")
        if label in UTIL_LABELS and len(columns) >= 2:
            values[UTIL_LABELS[label]] = parse_number(columns[1])
    return values


def load_result(build_dir: Path) -> TopImplResult:
    metadata = parse_metadata(build_dir / "metadata.txt")
    utilization_report = build_dir / "utilization_post_route.rpt"
    if metadata.get("result_stage") != "post_route" or not utilization_report.exists():
        utilization_report = build_dir / "utilization_post_synth.rpt"
    utilization = parse_utilization(utilization_report)
    return TopImplResult(
        part=metadata["part"],
        top=metadata["top"],
        pc=int(metadata["pc"]),
        pk=int(metadata["pk"]),
        max_cin=int(metadata["max_cin"]),
        max_cout=int(metadata["max_cout"]),
        max_pixels=int(metadata["max_pixels"]),
        period_ns=float(metadata["clock_period_ns"]),
        wns_ns=parse_optional_float(metadata["wns_ns"]),
        whs_ns=parse_optional_float(metadata["whs_ns"]),
        result_stage=metadata.get("result_stage", "unknown"),
        implementation_status=metadata.get("implementation_status", "unknown"),
        implementation_error_file=metadata.get("implementation_error_file"),
        luts=int(utilization["luts"]),
        registers=int(utilization["registers"]),
        f7_muxes=int(utilization.get("f7_muxes", 0)),
        f8_muxes=int(utilization.get("f8_muxes", 0)),
        bram_tiles=utilization["bram_tiles"],
        dsps=int(utilization["dsps"]),
    )


def render_markdown(result: TopImplResult, build_dir: Path) -> str:
    wns = "NA" if result.wns_ns is None else f"{result.wns_ns:.3f} ns"
    whs = "NA" if result.whs_ns is None else f"{result.whs_ns:.3f} ns"
    routed = result.result_stage == "post_route" and result.implementation_status == "passed"
    status_label = result.implementation_status
    if routed and not result.timing_met:
        status_label = "routed_timing_failed"
    timing_label = result.timing_met if routed else "not routed"
    checkpoint = "top_routed.dcp" if routed else "top_synth.dcp"
    timing_report = "timing_post_route.rpt" if routed else "timing_post_synth.rpt"
    utilization_report = "utilization_post_route.rpt" if routed else "utilization_post_synth.rpt"
    lines = [
        "# Top-Level Implementation Experiment",
        "",
        "This is an out-of-context implementation experiment for the image-to-image RTL top. "
        "It is not a board-ready Zynq block-design bitstream. If implementation does not "
        "fit, this report captures the post-synthesis evidence and failure reason.",
        "",
        "## Configuration",
        "",
        "| Field | Value |",
        "|---|---:|",
        f"| Part | `{result.part}` |",
        f"| Top | `{result.top}` |",
        f"| PC | {result.pc} |",
        f"| PK | {result.pk} |",
        f"| MAX_CIN | {result.max_cin} |",
        f"| MAX_COUT | {result.max_cout} |",
        f"| MAX_PIXELS | {result.max_pixels} |",
        f"| Clock target | {1000.0 / result.period_ns:.3f} MHz ({result.period_ns:.3f} ns) |",
        f"| Result stage | `{result.result_stage}` |",
        f"| Implementation status | `{status_label}` |",
        "",
        "## Timing",
        "",
        "| Metric | Value |",
        "|---|---:|",
        f"| WNS | {wns} |",
        f"| WHS | {whs} |",
        f"| Estimated setup Fmax | {result.estimated_fmax_mhz:.1f} MHz |",
        f"| Timing met | {timing_label} |",
        "",
        "## Utilization",
        "",
        "| Resource | Used |",
        "|---|---:|",
        f"| Slice LUTs | {result.luts:,} |",
        f"| Slice Registers | {result.registers:,} |",
        f"| F7 Muxes | {result.f7_muxes:,} |",
        f"| F8 Muxes | {result.f8_muxes:,} |",
        f"| Block RAM Tile | {result.bram_tiles:g} |",
        f"| DSPs | {result.dsps:,} |",
        "",
        "## Artifacts",
        "",
        f"- Checkpoint: `{build_dir / checkpoint}`",
        f"- Timing report: `{build_dir / timing_report}`",
        f"- Utilization report: `{build_dir / utilization_report}`",
    ]
    if routed:
        lines.extend(
            [
                f"- Hold timing report: `{build_dir / 'timing_hold_post_route.rpt'}`",
                f"- DRC report: `{build_dir / 'drc_post_route.rpt'}`",
            ]
        )
    elif result.implementation_error_file:
        lines.append(f"- Implementation failure: `{result.implementation_error_file}`")

    lines.extend(
        [
            "",
            "## Interpretation",
            "",
        ]
    )
    if routed and result.timing_met:
        lines.append(
            "The current top fits, routes, and meets the 125 MHz internal clock target in this "
            "out-of-context smoke configuration."
        )
    elif routed:
        lines.append(
            "The current top now fits and routes in this out-of-context smoke configuration, "
            "but it does not yet meet the 125 MHz internal clock target. The dominant remaining "
            "issue is timing through scratchpad address generation and BRAM read/write control."
        )
    else:
        lines.append(
            "The current top synthesizes but does not yet fit the Arty Z7-20 target in this "
            "configuration. The dominant issue is LUT/MUX pressure from wide generated selection "
            "logic around the stream-loaded controller and remaining full-frame/reference storage."
        )

    if routed and result.timing_met:
        lines.append(
            "The next board-facing step is integrating `cnn_image2image_system_top` into a "
            "Zynq block design with PS, AXI DMA, resets, clocking, physical constraints, "
            "and board-level timing evidence."
        )
    else:
        lines.append(
            "The next board-facing step is reducing the timing-critical scratchpad address/control "
            "paths, then rerunning this OOC implementation experiment before integrating "
            "`cnn_image2image_system_top` into a Zynq block design with PS, AXI DMA, resets, "
            "clocking, and physical constraints."
        )

    lines.extend(
        [
            "",
            "Regenerate:",
            "",
            "```bash",
            "make top-impl",
            "```",
            "",
            "Scale the experiment explicitly when needed:",
            "",
            "```bash",
            "PC=4 PK=8 MAX_PIXELS=64 make top-impl",
            "```",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-dir", type=Path, default=Path("build/top_impl"))
    parser.add_argument("--markdown", type=Path, default=Path("docs/top_implementation.md"))
    args = parser.parse_args()

    result = load_result(args.build_dir)
    args.markdown.parent.mkdir(parents=True, exist_ok=True)
    args.markdown.write_text(render_markdown(result, args.build_dir))
    print(args.markdown.read_text())
    print(f"Wrote {args.markdown}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
