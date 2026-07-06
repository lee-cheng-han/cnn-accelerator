#!/usr/bin/env python3
"""Summarize the current pre-board FPGA/software build state."""

from __future__ import annotations

import re
from datetime import datetime
from pathlib import Path


TIMING_RPT = Path("build/arty_z7_20_bitstream_timing.rpt")
UTIL_RPT = Path("build/arty_z7_20_bitstream_util.rpt")
FLOW_RPT = Path("build/flow_report.md")
BITSTREAM = Path("build/arty_z7_20_cnn/arty_z7_20_cnn.runs/impl_1/system_wrapper.bit")
XSA = Path("build/arty_z7_20_cnn/arty_z7_20_cnn.xsa")
PLATFORM_XSA = Path("build/vitis_ws/arty_z7_20_cnn_platform/hw/arty_z7_20_cnn.xsa")
ELF = Path("build/vitis_ws/cnn_baremetal/build/cnn_baremetal.elf")
FSBL = Path("build/vitis_ws/arty_z7_20_cnn_platform/zynq_fsbl/build/fsbl.elf")
BOOT_BIN = Path("build/BOOT.BIN")
DMA_LOG = Path("docs/logs/dma_top_sim_pass.log")


def parse_timing() -> dict[str, str]:
    if not TIMING_RPT.exists():
        return {}

    text = TIMING_RPT.read_text(errors="replace")
    values: dict[str, str] = {}
    match = re.search(
        r"^\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s+"
        r"(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)",
        text,
        re.MULTILINE,
    )
    if match:
        keys = [
            "WNS",
            "TNS",
            "TNS failing endpoints",
            "TNS total endpoints",
            "WHS",
            "THS",
            "THS failing endpoints",
            "THS total endpoints",
        ]
        values.update(dict(zip(keys, match.groups())))

    values["constraints_met"] = "All user specified timing constraints are met." in text
    clock = re.search(r"^clk_fpga_0\s+\{[^}]+\}\s+(\d+\.\d+)\s+(\d+\.\d+)", text, re.MULTILINE)
    if clock:
        values["clock_period_ns"] = clock.group(1)
        values["clock_mhz"] = clock.group(2)
    return values


def parse_utilization() -> dict[str, tuple[str, str, str]]:
    if not UTIL_RPT.exists():
        return {}

    util: dict[str, tuple[str, str, str]] = {}
    wanted = {
        "Slice LUTs": "Slice LUTs",
        "Slice Registers": "Slice Registers",
        "Block RAM Tile": "Block RAM Tile",
        "DSPs": "DSPs",
    }

    for line in UTIL_RPT.read_text(errors="replace").splitlines():
        for key, label in wanted.items():
            if f"| {key}" in line and label not in util:
                cols = [col.strip() for col in line.strip().strip("|").split("|")]
                if len(cols) >= 5:
                    util[label] = (cols[1], cols[4], cols[5] if len(cols) > 5 else "")
    return util


def status(path: Path) -> str:
    return "present" if path.exists() else "missing"


def render() -> str:
    timing = parse_timing()
    util = parse_utilization()
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    lines = [
        "# Pre-Board Flow Report",
        "",
        f"Generated: {now}",
        "",
        "## Artifacts",
        "",
        "| Artifact | Status | Path |",
        "|---|---|---|",
        f"| Bitstream | {status(BITSTREAM)} | `{BITSTREAM}` |",
        f"| Vivado-exported XSA | {status(XSA)} | `{XSA}` |",
        f"| Vitis platform XSA copy | {status(PLATFORM_XSA)} | `{PLATFORM_XSA}` |",
        f"| Bare-metal ELF | {status(ELF)} | `{ELF}` |",
        f"| FSBL | {status(FSBL)} | `{FSBL}` |",
        f"| BOOT.BIN | {status(BOOT_BIN)} | `{BOOT_BIN}` |",
        f"| DMA simulation proof log | {status(DMA_LOG)} | `{DMA_LOG}` |",
        "",
        "## Timing",
        "",
    ]

    if timing:
        lines.extend(
            [
                "| Metric | Value |",
                "|---|---:|",
                f"| Clock | {timing.get('clock_mhz', 'unknown')} MHz |",
                f"| Period | {timing.get('clock_period_ns', 'unknown')} ns |",
                f"| WNS | {timing.get('WNS', 'unknown')} ns |",
                f"| TNS | {timing.get('TNS', 'unknown')} ns |",
                f"| Failing setup endpoints | {timing.get('TNS failing endpoints', 'unknown')} |",
                f"| WHS | {timing.get('WHS', 'unknown')} ns |",
                f"| THS | {timing.get('THS', 'unknown')} ns |",
                f"| Failing hold endpoints | {timing.get('THS failing endpoints', 'unknown')} |",
                f"| Constraints met | {timing.get('constraints_met', False)} |",
            ]
        )
    else:
        lines.append("Timing report missing. Run `make arty-z7-bitstream`.")

    lines.extend(["", "## Utilization", ""])

    if util:
        lines.extend(["| Resource | Used | Available | Utilization |", "|---|---:|---:|---:|"])
        for resource in ["Slice LUTs", "Slice Registers", "Block RAM Tile", "DSPs"]:
            used, available, pct = util.get(resource, ("unknown", "unknown", "unknown"))
            lines.append(f"| {resource} | {used} | {available} | {pct}% |")
    else:
        lines.append("Utilization report missing. Run `make arty-z7-bitstream`.")

    lines.extend(
        [
            "",
            "## Next Hardware Evidence",
            "",
            "- UART log with `[PASS] CNN DMA accelerator test passed`.",
            "- Photo or screenshot of programmed Arty Z7-20 setup.",
            "- Measured board latency/throughput for the generated 8x8 3x3 test.",
            "- Any ILA or debug capture used during first bring-up.",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    FLOW_RPT.parent.mkdir(parents=True, exist_ok=True)
    report = render()
    FLOW_RPT.write_text(report)
    print(report)
    print(f"Wrote {FLOW_RPT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
