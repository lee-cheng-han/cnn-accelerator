"""Generate file-based golden tensors for the experimental image CNN RTL."""

from __future__ import annotations

import argparse
import random
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

from models.image2image_int8 import (
    DEFAULT_DENOISE_QUANT_SHIFTS,
    LayerConfig,
    conv2d_layer_int8,
    make_default_denoise_parameters,
    make_denoise_layer_configs,
    run_layers_int8,
    tensor_shape_hwc,
)


MAX_CIN = 16
MAX_COUT = 16
MAX_PIXELS = 64

CFG_INPUT_WIDTH = 0
CFG_INPUT_HEIGHT = 1
CFG_OUTPUT_WIDTH = 2
CFG_OUTPUT_HEIGHT = 3
CFG_KERNEL_SIZE = 4
CFG_STRIDE = 5
CFG_PADDING = 6
CFG_CIN = 7
CFG_COUT = 8
CFG_BIAS_ENABLE = 9
CFG_RELU_ENABLE = 10
CFG_QUANT_ENABLE = 11
CFG_QUANT_SHIFT = 12
CFG_WORDS = 13

FULL_CFG_INPUT_WIDTH = 0
FULL_CFG_INPUT_HEIGHT = 1
FULL_CFG_OUTPUT_WIDTH = 2
FULL_CFG_OUTPUT_HEIGHT = 3
FULL_CFG_FINAL_RESIDUAL_ENABLE = 4
FULL_CFG_WORDS = 5


def int_to_hex(value: int, bits: int) -> str:
    mask = (1 << bits) - 1
    width = bits // 4
    return f"{int(value) & mask:0{width}x}"


def make_random_tensor(height: int, width: int, channels: int, rng: random.Random) -> list[list[list[int]]]:
    return [
        [[rng.randint(-12, 12) for _ in range(channels)] for _ in range(width)]
        for _ in range(height)
    ]


def make_random_weights(
    cout: int,
    cin: int,
    kernel: int,
    rng: random.Random,
    low: int = -5,
    high: int = 5,
) -> list[list[list[list[int]]]]:
    return [
        [
            [[rng.randint(low, high) for _ in range(kernel)] for _ in range(kernel)]
            for _ in range(cin)
        ]
        for _ in range(cout)
    ]


def write_mem(path: Path, values: list[int], bits: int) -> None:
    path.write_text("".join(f"{int_to_hex(value, bits)}\n" for value in values), encoding="utf-8")


def flatten_activation(x, *, input_width: int, input_height: int, cin: int) -> list[int]:
    flat = [0 for _ in range(MAX_PIXELS * MAX_CIN)]

    for y in range(input_height):
        for x_idx in range(input_width):
            for ci in range(cin):
                flat[((y * input_width + x_idx) * MAX_CIN) + ci] = int(x[y][x_idx][ci])

    return flat


def flatten_weights_1x1(weights, *, cout: int, cin: int) -> list[int]:
    flat = [0 for _ in range(MAX_COUT * MAX_CIN)]

    for co in range(cout):
        for ci in range(cin):
            flat[(co * MAX_CIN) + ci] = int(weights[co][ci][0][0])

    return flat


def flatten_weights_3x3(weights, *, cout: int, cin: int, kernel_size: int) -> list[int]:
    flat = [0 for _ in range(MAX_COUT * MAX_CIN * 9)]

    for co in range(cout):
        for ci in range(cin):
            for ky in range(kernel_size):
                for kx in range(kernel_size):
                    k = (ky * 3) + kx
                    flat[((co * MAX_CIN + ci) * 9) + k] = int(weights[co][ci][ky][kx])

    return flat


def flatten_bias(bias: list[int], *, cout: int) -> list[int]:
    flat = [0 for _ in range(MAX_COUT)]

    for co in range(cout):
        flat[co] = int(bias[co])

    return flat


def flatten_output(y, *, output_width: int, output_height: int, cout: int) -> list[int]:
    flat = [0 for _ in range(MAX_PIXELS * MAX_COUT)]

    for oy in range(output_height):
        for ox in range(output_width):
            for co in range(cout):
                flat[((oy * output_width + ox) * MAX_COUT) + co] = int(y[oy][ox][co])

    return flat


def generate_full_network_case(out_dir: Path, *, name: str, seed: int, input_width: int, input_height: int) -> None:
    rng = random.Random(seed)
    out_dir.mkdir(parents=True, exist_ok=True)

    residual_configs = make_denoise_layer_configs(
        quant_shifts=DEFAULT_DENOISE_QUANT_SHIFTS,
        final_residual=True,
    )
    no_residual_configs = make_denoise_layer_configs(
        quant_shifts=DEFAULT_DENOISE_QUANT_SHIFTS,
        final_residual=False,
    )
    x = make_random_tensor(input_height, input_width, 3, rng)
    default_parameters = make_default_denoise_parameters()
    weights = [layer_weights for layer_weights, _ in default_parameters]
    biases = [layer_bias for _, layer_bias in default_parameters]

    residual_layers = [
        (cfg, layer_weights, layer_bias)
        for cfg, layer_weights, layer_bias in zip(residual_configs, weights, biases)
    ]
    no_residual_layers = [
        (cfg, layer_weights, layer_bias)
        for cfg, layer_weights, layer_bias in zip(no_residual_configs, weights, biases)
    ]

    y_residual = run_layers_int8(x, residual_layers)
    y_no_residual = run_layers_int8(x, no_residual_layers)
    output_height, output_width_model, output_channels = tensor_shape_hwc(y_residual)

    if output_width_model != input_width or output_height != input_height:
        raise ValueError(
            f"{name}: expected same-sized image output, got {output_width_model}x{output_height}"
        )
    if input_width * input_height > MAX_PIXELS:
        raise ValueError(f"{name}: input tensor exceeds MAX_PIXELS={MAX_PIXELS}")
    if output_channels != 3:
        raise ValueError(f"{name}: output channel mismatch")

    config = [0 for _ in range(FULL_CFG_WORDS)]
    config[FULL_CFG_INPUT_WIDTH] = input_width
    config[FULL_CFG_INPUT_HEIGHT] = input_height
    config[FULL_CFG_OUTPUT_WIDTH] = output_width_model
    config[FULL_CFG_OUTPUT_HEIGHT] = output_height
    config[FULL_CFG_FINAL_RESIDUAL_ENABLE] = 1

    write_mem(out_dir / "config.mem", config, 32)
    write_mem(
        out_dir / "input.mem",
        flatten_activation(x, input_width=input_width, input_height=input_height, cin=3),
        8,
    )

    for layer_idx, (cfg, layer_weights, layer_bias) in enumerate(zip(residual_configs, weights, biases)):
        write_mem(
            out_dir / f"weights_l{layer_idx}.mem",
            flatten_weights_3x3(
                layer_weights,
                cout=cfg.output_channels,
                cin=cfg.input_channels,
                kernel_size=cfg.kernel_size,
            ),
            8,
        )
        write_mem(out_dir / f"bias_l{layer_idx}.mem", flatten_bias(layer_bias, cout=cfg.output_channels), 32)

    write_mem(
        out_dir / "expected_residual.mem",
        flatten_output(y_residual, output_width=output_width_model, output_height=output_height, cout=3),
        8,
    )
    write_mem(
        out_dir / "expected_no_residual.mem",
        flatten_output(y_no_residual, output_width=output_width_model, output_height=output_height, cout=3),
        8,
    )

    summary = [
        f"name={name}",
        f"seed={seed}",
        f"input_width={input_width}",
        f"input_height={input_height}",
        f"output_width={output_width_model}",
        f"output_height={output_height}",
        "network=default Gaussian low-pass denoiser, 3x3 3->16->16->3",
        "parameters=deterministic signed RGB features and Gaussian high-pass residual",
        "bias_enable=1",
        "quant_enable=1",
        "quant_shift=0,5,1",
        "expected_residual=output = input - predicted_noise",
    ]
    (out_dir / "summary.txt").write_text("\n".join(summary) + "\n", encoding="utf-8")


def generate_case(
    out_dir: Path,
    *,
    name: str,
    seed: int,
    cfg: LayerConfig,
    input_width: int,
    input_height: int,
) -> None:
    rng = random.Random(seed)
    out_dir.mkdir(parents=True, exist_ok=True)

    x = make_random_tensor(input_height, input_width, cfg.input_channels, rng)
    weights = make_random_weights(cfg.output_channels, cfg.input_channels, cfg.kernel_size, rng)
    bias = [rng.randint(-24, 24) for _ in range(cfg.output_channels)]
    y = conv2d_layer_int8(x, weights, bias, cfg)
    output_height, output_width, output_channels = tensor_shape_hwc(y)

    if output_width * output_height > MAX_PIXELS:
        raise ValueError(f"{name}: output tensor exceeds MAX_PIXELS={MAX_PIXELS}")
    if output_channels != cfg.output_channels:
        raise ValueError(f"{name}: output channel mismatch")

    config = [0 for _ in range(CFG_WORDS)]
    config[CFG_INPUT_WIDTH] = input_width
    config[CFG_INPUT_HEIGHT] = input_height
    config[CFG_OUTPUT_WIDTH] = output_width
    config[CFG_OUTPUT_HEIGHT] = output_height
    config[CFG_KERNEL_SIZE] = cfg.kernel_size
    config[CFG_STRIDE] = cfg.stride
    config[CFG_PADDING] = cfg.padding
    config[CFG_CIN] = cfg.input_channels
    config[CFG_COUT] = cfg.output_channels
    config[CFG_BIAS_ENABLE] = int(cfg.bias_enable)
    config[CFG_RELU_ENABLE] = int(cfg.relu_enable)
    config[CFG_QUANT_ENABLE] = int(cfg.quant_enable)
    config[CFG_QUANT_SHIFT] = cfg.quant_shift

    write_mem(out_dir / "config.mem", config, 32)
    write_mem(
        out_dir / "activation.mem",
        flatten_activation(x, input_width=input_width, input_height=input_height, cin=cfg.input_channels),
        8,
    )
    write_mem(
        out_dir / "weights_1x1.mem",
        flatten_weights_1x1(weights, cout=cfg.output_channels, cin=cfg.input_channels)
        if cfg.kernel_size == 1 else [0 for _ in range(MAX_COUT * MAX_CIN)],
        8,
    )
    write_mem(
        out_dir / "weights_3x3.mem",
        flatten_weights_3x3(
            weights,
            cout=cfg.output_channels,
            cin=cfg.input_channels,
            kernel_size=cfg.kernel_size,
        )
        if cfg.kernel_size == 3 else [0 for _ in range(MAX_COUT * MAX_CIN * 9)],
        8,
    )
    write_mem(out_dir / "bias.mem", flatten_bias(bias, cout=cfg.output_channels), 32)
    write_mem(
        out_dir / "expected.mem",
        flatten_output(y, output_width=output_width, output_height=output_height, cout=cfg.output_channels),
        8,
    )

    summary = [
        f"name={name}",
        f"seed={seed}",
        f"input_width={input_width}",
        f"input_height={input_height}",
        f"output_width={output_width}",
        f"output_height={output_height}",
        f"input_channels={cfg.input_channels}",
        f"output_channels={cfg.output_channels}",
        f"kernel_size={cfg.kernel_size}",
        f"stride={cfg.stride}",
        f"padding={cfg.padding}",
        f"bias_enable={int(cfg.bias_enable)}",
        f"relu_enable={int(cfg.relu_enable)}",
        f"quant_enable={int(cfg.quant_enable)}",
        f"quant_shift={cfg.quant_shift}",
    ]
    (out_dir / "summary.txt").write_text("\n".join(summary) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", default="build/golden", help="Output directory")
    args = parser.parse_args()

    out_root = Path(args.out_dir)

    generate_case(
        out_root / "single_layer_1x1",
        name="single_layer_1x1",
        seed=101,
        input_width=4,
        input_height=3,
        cfg=LayerConfig(
            input_channels=3,
            output_channels=5,
            kernel_size=1,
            stride=1,
            padding=0,
            bias_enable=True,
            relu_enable=True,
            quant_enable=True,
            quant_shift=1,
        ),
    )
    generate_case(
        out_root / "single_layer_3x3",
        name="single_layer_3x3",
        seed=202,
        input_width=5,
        input_height=4,
        cfg=LayerConfig(
            input_channels=7,
            output_channels=13,
            kernel_size=3,
            stride=1,
            padding=1,
            bias_enable=True,
            relu_enable=True,
            quant_enable=True,
            quant_shift=1,
        ),
    )
    generate_full_network_case(
        out_root / "full_network_3layer",
        name="full_network_3layer",
        seed=303,
        input_width=4,
        input_height=3,
    )

    print(f"Wrote golden tensor fixtures to {out_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
