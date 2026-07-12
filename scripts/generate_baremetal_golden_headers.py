"""Generate C headers for the bare-metal golden DMA test."""

from __future__ import annotations

import argparse
from pathlib import Path

MAX_CIN = 16
MAX_COUT = 16
INPUT_C = 3
HIDDEN_C = 16
OUTPUT_C = 3
HEADER_MAGIC = 0xA5

CFG_INPUT_WIDTH = 0
CFG_INPUT_HEIGHT = 1
CFG_OUTPUT_WIDTH = 2
CFG_OUTPUT_HEIGHT = 3
CFG_FINAL_RESIDUAL_ENABLE = 4


def parse_mem(path: Path, bits: int) -> list[int]:
    mask = (1 << bits) - 1
    sign = 1 << (bits - 1)
    values: list[int] = []

    for line in path.read_text(encoding="utf-8").splitlines():
        text = line.strip()
        if not text:
            continue
        value = int(text, 16) & mask
        if value & sign:
            value -= 1 << bits
        values.append(value)

    return values


def payload_i8(value: int) -> int:
    return int(value) & 0xFF


def payload_i32(value: int) -> int:
    return int(value) & 0xFFFFFFFF


def packet_header(packet_type: int) -> int:
    return (HEADER_MAGIC << 24) | ((packet_type & 0xFF) << 16)


def append_activation_packet(words: list[int], input_mem: list[int], pixels: int) -> None:
    words.append(packet_header(0))
    for pixel in range(pixels):
        for channel in range(INPUT_C):
            words.append(payload_i8(input_mem[(pixel * MAX_CIN) + channel]))


def append_bias_packet(words: list[int], packet_type: int, bias_mem: list[int], count: int) -> None:
    words.append(packet_header(packet_type))
    for idx in range(count):
        words.append(payload_i32(bias_mem[idx]))


def append_weight_packet(
    words: list[int],
    packet_type: int,
    weights_mem: list[int],
    cout: int,
    cin: int,
) -> None:
    words.append(packet_header(packet_type))
    for co in range(cout):
        for ci in range(cin):
            for tap in range(9):
                words.append(payload_i8(weights_mem[((co * MAX_CIN + ci) * 9) + tap]))


def expected_outputs(expected_mem: list[int], pixels: int) -> list[int]:
    values: list[int] = []
    for pixel in range(pixels):
        for channel in range(OUTPUT_C):
            values.append(int(expected_mem[(pixel * MAX_COUT) + channel]))
    return values


def format_array(values: list[int], c_type: str, name: str, per_line: int = 4) -> str:
    lines = [f"static const {c_type} {name}[{len(values)}] = {{"]
    for idx in range(0, len(values), per_line):
        chunk = values[idx : idx + per_line]
        if c_type == "uint32_t":
            body = ", ".join(f"0x{value & 0xFFFFFFFF:08x}U" for value in chunk)
        else:
            body = ", ".join(f"{value}" for value in chunk)
        lines.append(f"    {body},")
    lines.append("};")
    return "\n".join(lines)


def generate(case_dir: Path, out_dir: Path) -> None:
    config = parse_mem(case_dir / "config.mem", 32)
    width = config[CFG_INPUT_WIDTH]
    height = config[CFG_INPUT_HEIGHT]
    output_width = config[CFG_OUTPUT_WIDTH]
    output_height = config[CFG_OUTPUT_HEIGHT]
    pixels = width * height
    output_words = output_width * output_height * OUTPUT_C

    input_mem = parse_mem(case_dir / "input.mem", 8)
    bias_l0 = parse_mem(case_dir / "bias_l0.mem", 32)
    bias_l1 = parse_mem(case_dir / "bias_l1.mem", 32)
    bias_l2 = parse_mem(case_dir / "bias_l2.mem", 32)
    weights_l0 = parse_mem(case_dir / "weights_l0.mem", 8)
    weights_l1 = parse_mem(case_dir / "weights_l1.mem", 8)
    weights_l2 = parse_mem(case_dir / "weights_l2.mem", 8)
    expected_residual_mem = parse_mem(case_dir / "expected_residual.mem", 8)
    expected_no_residual_mem = parse_mem(case_dir / "expected_no_residual.mem", 8)

    packets: list[int] = []
    append_activation_packet(packets, input_mem, pixels)
    append_bias_packet(packets, 1, bias_l0, HIDDEN_C)
    append_weight_packet(packets, 2, weights_l0, HIDDEN_C, INPUT_C)
    append_bias_packet(packets, 3, bias_l1, HIDDEN_C)
    append_weight_packet(packets, 4, weights_l1, HIDDEN_C, HIDDEN_C)
    append_bias_packet(packets, 5, bias_l2, OUTPUT_C)
    append_weight_packet(packets, 6, weights_l2, OUTPUT_C, HIDDEN_C)

    expected_residual = expected_outputs(expected_residual_mem, output_words // OUTPUT_C)
    expected_no_residual = expected_outputs(expected_no_residual_mem, output_words // OUTPUT_C)

    out_dir.mkdir(parents=True, exist_ok=True)
    header = out_dir / "golden_dma_job.h"
    text = [
        "#ifndef GOLDEN_DMA_JOB_H",
        "#define GOLDEN_DMA_JOB_H",
        "",
        "#include <stdint.h>",
        "",
        f"#define IMAGE_WIDTH {width}U",
        f"#define IMAGE_HEIGHT {height}U",
        f"#define OUTPUT_WIDTH {output_width}U",
        f"#define OUTPUT_HEIGHT {output_height}U",
        f"#define INPUT_PIXELS {pixels}U",
        f"#define OUTPUT_WORDS {output_words}U",
        f"#define INPUT_PACKET_WORDS {len(packets)}U",
        f"#define FINAL_RESIDUAL_DEFAULT {config[CFG_FINAL_RESIDUAL_ENABLE]}U",
        "",
        format_array(packets, "uint32_t", "input_packet_words"),
        "",
        format_array(expected_residual, "int32_t", "expected_residual_words", per_line=8),
        "",
        format_array(expected_no_residual, "int32_t", "expected_no_residual_words", per_line=8),
        "",
        "#endif",
        "",
    ]
    header.write_text("\n".join(text), encoding="utf-8")
    print(f"Wrote {header}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--case-dir",
        default="build/golden/full_network_3layer",
        help="Generated full-network golden case directory",
    )
    parser.add_argument(
        "--out-dir",
        default="software/zynq_baremetal/generated",
        help="Output directory for generated C headers",
    )
    args = parser.parse_args()

    generate(Path(args.case_dir), Path(args.out_dir))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
