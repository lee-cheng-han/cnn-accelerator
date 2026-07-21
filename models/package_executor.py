"""Bit-accurate executor driven exclusively by a serialized V1 package."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import struct
import sys
from typing import Sequence

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from models.cnn_abi import (
    Activation,
    LayerFlags,
    ResidualMode,
    parse_model_package,
)
from models.image2image_int8 import (
    Tensor3D,
    apply_residual,
    copy_int8_tensor,
    requantize_int32,
    tensor_shape_hwc,
    zeros_hwc,
)


def _decode_int8(data: bytes) -> list[int]:
    return [byte - 256 if byte >= 128 else byte for byte in data]


def _decode_weights(data: bytes, cout: int, cin: int, kernel: int):
    values = _decode_int8(data)
    cursor = 0
    weights = []
    for _co in range(cout):
        output_channel = []
        for _ci in range(cin):
            input_channel = []
            for _ky in range(kernel):
                input_channel.append(values[cursor:cursor + kernel])
                cursor += kernel
            output_channel.append(input_channel)
        weights.append(output_channel)
    return weights


def _run_layer(source, weights, bias, layer, output_tensor, quantization):
    input_height, input_width, input_channels = tensor_shape_hwc(source)
    output = zeros_hwc(output_tensor.height, output_tensor.width, output_tensor.channels)
    for oy in range(output_tensor.height):
        for ox in range(output_tensor.width):
            for co in range(output_tensor.channels):
                accumulator = 0
                for ky in range(layer.kernel_height):
                    iy = oy * layer.stride_y + ky - layer.padding_top
                    if iy < 0 or iy >= input_height:
                        continue
                    for kx in range(layer.kernel_width):
                        ix = ox * layer.stride_x + kx - layer.padding_left
                        if ix < 0 or ix >= input_width:
                            continue
                        for ci in range(input_channels):
                            accumulator += int(source[iy][ix][ci]) * int(weights[co][ci][ky][kx])
                biased = accumulator + (
                    bias[co] if layer.flags & LayerFlags.BIAS_ENABLE else 0
                )
                if layer.activation == Activation.RELU and biased < 0:
                    biased = 0
                output[oy][ox][co] = requantize_int32(
                    biased,
                    quantization.quant_multipliers[co],
                    quantization.quant_shifts[co],
                    quantization.output_zero_point,
                )
    return output


def execute_model_package(
    package: bytes,
    input_tensor: Sequence[Sequence[Sequence[int]]],
    *,
    return_tensors: bool = False,
):
    """Execute a validated package and return its output NHWC INT8 tensor."""
    header, layers, tensor_descriptors, quantizations = parse_model_package(package)
    tensor_by_id = {tensor.tensor_id: tensor for tensor in tensor_descriptors}
    quant_by_id = {quant.quantization_id: quant for quant in quantizations}
    input_descriptor = tensor_by_id[header.input_tensor_id]
    actual_shape = tensor_shape_hwc(input_tensor)
    expected_shape = (
        input_descriptor.height,
        input_descriptor.width,
        input_descriptor.channels,
    )
    if actual_shape != expected_shape:
        raise ValueError(f"input tensor shape {actual_shape} does not match package {expected_shape}")
    for y, row in enumerate(input_tensor):
        for x, pixel in enumerate(row):
            for channel, value in enumerate(pixel):
                if isinstance(value, bool) or not isinstance(value, int):
                    raise ValueError(
                        f"input[{y}][{x}][{channel}] must be an integer"
                    )
                if not -128 <= value <= 127:
                    raise ValueError(f"input[{y}][{x}][{channel}]={value} is outside signed INT8")

    tensors: dict[int, Tensor3D] = {
        header.input_tensor_id: copy_int8_tensor(input_tensor)
    }
    for layer in layers:
        source = tensors[layer.input_tensor_id]
        input_desc = tensor_by_id[layer.input_tensor_id]
        output_desc = tensor_by_id[layer.output_tensor_id]
        weight_data = package[layer.weight_offset:layer.weight_offset + layer.weight_size]
        weights = _decode_weights(
            weight_data, output_desc.channels, input_desc.channels, layer.kernel_width
        )
        if layer.flags & LayerFlags.BIAS_ENABLE:
            bias_data = package[layer.bias_offset:layer.bias_offset + layer.bias_size]
            bias = list(struct.unpack(f"<{output_desc.channels}i", bias_data))
        else:
            bias = [0] * output_desc.channels
        output = _run_layer(
            source, weights, bias, layer, output_desc,
            quant_by_id[layer.quantization_id],
        )
        if layer.residual_mode != ResidualMode.NONE:
            residual = tensors[layer.residual_tensor_id]
            mode = "add" if layer.residual_mode == ResidualMode.POST_QUANT_ADD else "sub"
            output = apply_residual(residual, output, mode)
        tensors[layer.output_tensor_id] = output

    result = tensors[header.output_tensor_id]
    return (result, tensors) if return_tensors else result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path, help="Compiled V1 .cnn package")
    parser.add_argument("input", type=Path, help="NHWC input tensor JSON")
    parser.add_argument("-o", "--output", type=Path, required=True, help="Output tensor JSON")
    args = parser.parse_args()
    result = execute_model_package(
        args.package.read_bytes(), json.loads(args.input.read_text(encoding="utf-8"))
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
