"""Compile a human-readable CNN model specification into a V1 package."""

from __future__ import annotations

import argparse
import dataclasses
import json
from pathlib import Path
import struct
import sys
from typing import Any, Mapping, Sequence

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from models.cnn_abi import (
    LAYER_DESCRIPTOR_SIZE,
    MODEL_HEADER_SIZE,
    QUANT_DESCRIPTOR_SIZE,
    RECORD_ALIGNMENT,
    TENSOR_DESCRIPTOR_SIZE,
    Activation,
    LayerDescriptor,
    LayerFlags,
    ModelHeader,
    NO_TENSOR_ID,
    QuantizationDescriptor,
    ResidualMode,
    TensorDescriptor,
    TensorFlags,
    compute_package_crc32,
    compute_package_sha256,
    parameter_crc32,
    parse_model_package,
    validate_model,
)


MODEL_SPEC_FORMAT = "cnn-accelerator-model-v1"


class CompilerError(ValueError):
    """Raised when a source model cannot be represented by the V1 ABI."""


def align_up(value: int, alignment: int) -> int:
    if alignment <= 0 or alignment & (alignment - 1):
        raise CompilerError("alignment must be a positive power of two")
    return (int(value) + alignment - 1) & ~(alignment - 1)


def _require_mapping(value: Any, field: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise CompilerError(f"{field} must be an object")
    return value


def _require_int(value: Any, field: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise CompilerError(f"{field} must be an integer")
    return value


def _require_bool(value: Any, field: str) -> bool:
    if not isinstance(value, bool):
        raise CompilerError(f"{field} must be true or false")
    return value


def _axis_pair(value: Any, field: str) -> tuple[int, int]:
    if isinstance(value, int) and not isinstance(value, bool):
        return value, value
    if isinstance(value, Sequence) and not isinstance(value, (str, bytes)) and len(value) == 2:
        return _require_int(value[0], f"{field}[0]"), _require_int(value[1], f"{field}[1]")
    raise CompilerError(f"{field} must be an integer or [y, x]")


def _padding(value: Any, field: str) -> tuple[int, int, int, int]:
    if isinstance(value, int) and not isinstance(value, bool):
        return value, value, value, value
    if isinstance(value, Sequence) and not isinstance(value, (str, bytes)) and len(value) == 4:
        return tuple(_require_int(item, f"{field}[{index}]") for index, item in enumerate(value))
    if isinstance(value, Mapping):
        return tuple(
            _require_int(value.get(edge), f"{field}.{edge}")
            for edge in ("top", "bottom", "left", "right")
        )
    raise CompilerError(f"{field} must be an integer, [top, bottom, left, right], or object")


def _flatten_nested(value: Any) -> list[Any]:
    if isinstance(value, Sequence) and not isinstance(value, (str, bytes, bytearray)):
        result = []
        for item in value:
            result.extend(_flatten_nested(item))
        return result
    return [value]


def _load_parameter_values(
    layer: Mapping[str, Any],
    name: str,
    count: int,
    bits: int,
    base_dir: Path,
    *,
    default_zero: bool = False,
) -> list[int]:
    inline_present = name in layer
    file_key = f"{name}_file"
    file_present = file_key in layer
    if inline_present and file_present:
        raise CompilerError(f"layer cannot define both {name} and {file_key}")

    if inline_present:
        values = _flatten_nested(layer[name])
    elif file_present:
        path = base_dir / str(layer[file_key])
        if not path.is_file():
            raise CompilerError(f"parameter file does not exist: {path}")
        if path.suffix.lower() == ".json":
            values = _flatten_nested(json.loads(path.read_text(encoding="utf-8")))
        elif path.suffix.lower() == ".bin":
            data = path.read_bytes()
            if bits == 8:
                values = [byte - 256 if byte >= 128 else byte for byte in data]
            else:
                if len(data) % 4:
                    raise CompilerError(f"{path} INT32 byte count is not divisible by four")
                values = list(struct.unpack(f"<{len(data) // 4}i", data))
        else:
            raise CompilerError(f"{path} must use .json or .bin parameter encoding")
    elif default_zero:
        values = [0] * count
    else:
        raise CompilerError(f"layer is missing required {name} or {file_key}")

    if len(values) != count:
        raise CompilerError(f"{name} requires {count} values, got {len(values)}")
    low = -(1 << (bits - 1))
    high = (1 << (bits - 1)) - 1
    normalized = []
    for index, value in enumerate(values):
        integer = _require_int(value, f"{name}[{index}]")
        if not low <= integer <= high:
            raise CompilerError(f"{name}[{index}]={integer} is outside signed INT{bits}")
        normalized.append(integer)
    return normalized


def _int8_bytes(values: Sequence[int]) -> bytes:
    return bytes(value & 0xFF for value in values)


def _int32_bytes(values: Sequence[int]) -> bytes:
    return struct.pack(f"<{len(values)}i", *values) if values else b""


def _allocate_workspace(tensors: list[dict[str, int]]) -> int:
    allocated: list[dict[str, int]] = []
    high_watermark = 0
    for tensor in tensors:
        candidate = 0
        while True:
            candidate = align_up(candidate, RECORD_ALIGNMENT)
            conflict = None
            for other in allocated:
                lifetime_overlap = (
                    tensor["lifetime_begin"] <= other["lifetime_end"]
                    and other["lifetime_begin"] <= tensor["lifetime_end"]
                )
                address_overlap = (
                    candidate < other["ddr_offset"] + other["allocation_size"]
                    and other["ddr_offset"] < candidate + tensor["allocation_size"]
                )
                if lifetime_overlap and address_overlap:
                    conflict = other
                    break
            if conflict is None:
                break
            candidate = conflict["ddr_offset"] + conflict["allocation_size"]
        tensor["ddr_offset"] = candidate
        allocated.append(tensor)
        high_watermark = max(high_watermark, candidate + tensor["allocation_size"])
    return align_up(high_watermark, RECORD_ALIGNMENT)


def compile_model(spec: Mapping[str, Any], *, base_dir: Path | str = ".") -> bytes:
    """Compile a model mapping into a deterministic, validated V1 package."""
    spec = _require_mapping(spec, "model")
    if spec.get("format") != MODEL_SPEC_FORMAT:
        raise CompilerError(f"format must be {MODEL_SPEC_FORMAT!r}")
    base_dir = Path(base_dir)
    model_id = _require_int(spec.get("model_id"), "model_id")
    generation_id = _require_int(spec.get("model_generation_id", 0), "model_generation_id")

    input_spec = _require_mapping(spec.get("input"), "input")
    input_name = str(input_spec.get("name", "input"))
    width = _require_int(input_spec.get("width"), "input.width")
    height = _require_int(input_spec.get("height"), "input.height")
    channels = _require_int(input_spec.get("channels"), "input.channels")
    if width <= 0 or height <= 0 or channels <= 0:
        raise CompilerError("input width, height, and channels must be positive")
    input_quant_profile = str(input_spec.get("quantization_profile", "input"))
    if not input_quant_profile:
        raise CompilerError("input.quantization_profile cannot be empty")

    raw_layers = spec.get("layers")
    if not isinstance(raw_layers, Sequence) or isinstance(raw_layers, (str, bytes)) or not raw_layers:
        raise CompilerError("layers must be a non-empty array")
    layer_specs = [_require_mapping(layer, f"layers[{index}]") for index, layer in enumerate(raw_layers)]
    if len(layer_specs) > 8:
        raise CompilerError("V1 supports at most eight layers")

    tensor_meta: list[dict[str, Any]] = [
        {
            "name": input_name,
            "tensor_id": 0,
            "width": width,
            "height": height,
            "channels": channels,
            "producer": 0,
            "consumers": [],
            "flags": TensorFlags.MODEL_INPUT,
        }
    ]
    tensor_by_name = {input_name: tensor_meta[0]}
    compiled_layers: list[dict[str, Any]] = []
    quant_profiles: dict[str, tuple[int, int]] = {}
    quantizations: list[QuantizationDescriptor] = []

    def quantization_for(profile: str, shift: int) -> int:
        existing = quant_profiles.get(profile)
        if existing is not None:
            quant_id, existing_shift = existing
            if existing_shift != shift:
                raise CompilerError(
                    f"quantization profile {profile!r} uses shifts {existing_shift} and {shift}"
                )
            return quant_id
        quant_id = len(quantizations)
        quant_profiles[profile] = (quant_id, shift)
        quantizations.append(QuantizationDescriptor(quant_id, quant_shift=shift))
        return quant_id

    current_name = input_name
    for index, layer in enumerate(layer_specs):
        name = str(layer.get("name", f"layer_{index}"))
        output_name = str(layer.get("output", "output" if index == len(layer_specs) - 1 else f"tensor_{index + 1}"))
        if output_name in tensor_by_name:
            raise CompilerError(f"duplicate tensor name {output_name!r}")
        input_tensor = tensor_by_name[current_name]
        output_channels = _require_int(layer.get("output_channels"), f"layers[{index}].output_channels")
        kernel = _require_int(layer.get("kernel_size", 3), f"layers[{index}].kernel_size")
        stride_y, stride_x = _axis_pair(layer.get("stride", 1), f"layers[{index}].stride")
        pad_top, pad_bottom, pad_left, pad_right = _padding(
            layer.get("padding", 0), f"layers[{index}].padding"
        )
        if output_channels <= 0:
            raise CompilerError(f"layer {name!r} output_channels must be positive")
        if kernel not in (1, 3):
            raise CompilerError(f"layer {name!r} kernel_size must be 1 or 3")
        if stride_y not in (1, 2) or stride_x not in (1, 2):
            raise CompilerError(f"layer {name!r} stride values must be 1 or 2")
        if any(padding not in (0, 1) for padding in (
            pad_top, pad_bottom, pad_left, pad_right
        )):
            raise CompilerError(f"layer {name!r} padding must be 0 or 1 per edge")
        output_width = ((input_tensor["width"] + pad_left + pad_right - kernel) // stride_x) + 1
        output_height = ((input_tensor["height"] + pad_top + pad_bottom - kernel) // stride_y) + 1
        if output_width <= 0 or output_height <= 0:
            raise CompilerError(f"layer {name!r} produces invalid shape {output_height}x{output_width}")

        activation_name = str(layer.get("activation", "none")).lower()
        activation_map = {"none": Activation.NONE, "relu": Activation.RELU}
        if activation_name not in activation_map:
            raise CompilerError(f"layer {name!r} activation must be 'none' or 'relu'")

        residual_name = layer.get("residual")
        residual_mode_name = str(layer.get("residual_mode", "none")).lower()
        residual_map = {
            "none": ResidualMode.NONE,
            "add": ResidualMode.POST_QUANT_ADD,
            "subtract": ResidualMode.POST_QUANT_SUBTRACT,
            "sub": ResidualMode.POST_QUANT_SUBTRACT,
        }
        if residual_mode_name not in residual_map:
            raise CompilerError(f"layer {name!r} has unsupported residual_mode")
        residual_mode = residual_map[residual_mode_name]
        if residual_mode == ResidualMode.NONE:
            if residual_name is not None:
                raise CompilerError(f"layer {name!r} names a residual tensor but mode is none")
            residual_tensor = None
        else:
            if not isinstance(residual_name, str) or residual_name not in tensor_by_name:
                raise CompilerError(f"layer {name!r} residual must name an earlier tensor")
            residual_tensor = tensor_by_name[residual_name]

        quant_shift = _require_int(layer.get("quant_shift", 0), f"layers[{index}].quant_shift")
        default_profile = input_quant_profile if residual_name == input_name else f"{name}.output"
        quant_profile = str(layer.get("quantization_profile", default_profile))
        if not quant_profile:
            raise CompilerError(f"layer {name!r} quantization_profile cannot be empty")
        quant_id = quantization_for(quant_profile, quant_shift)

        output_tensor = {
            "name": output_name,
            "tensor_id": len(tensor_meta),
            "width": output_width,
            "height": output_height,
            "channels": output_channels,
            "producer": index,
            "consumers": [],
            "flags": TensorFlags.MODEL_OUTPUT if index == len(layer_specs) - 1 else TensorFlags(0),
            "quantization_id": quant_id,
        }
        tensor_meta.append(output_tensor)
        tensor_by_name[output_name] = output_tensor
        input_tensor["consumers"].append(index)
        if residual_tensor is not None:
            residual_tensor["consumers"].append(index)

        weight_count = kernel * kernel * input_tensor["channels"] * output_channels
        bias_enable = _require_bool(
            layer.get("bias_enable", True), f"layers[{index}].bias_enable"
        )
        weights = _load_parameter_values(layer, "weights", weight_count, 8, base_dir)
        if not bias_enable and ("bias" in layer or "bias_file" in layer):
            raise CompilerError(f"layer {name!r} disables bias but provides bias parameters")
        biases = (
            _load_parameter_values(
                layer, "bias", output_channels, 32, base_dir, default_zero=True
            )
            if bias_enable else []
        )

        compiled_layers.append(
            {
                "name": name,
                "input": input_tensor,
                "output": output_tensor,
                "residual": residual_tensor,
                "residual_mode": residual_mode,
                "quantization_id": quant_id,
                "kernel": kernel,
                "stride_y": stride_y,
                "stride_x": stride_x,
                "padding": (pad_top, pad_bottom, pad_left, pad_right),
                "activation": activation_map[activation_name],
                "bias_enable": bias_enable,
                "weight_bytes": _int8_bytes(weights),
                "bias_bytes": _int32_bytes(biases),
                "tile_height_hint": _require_int(layer.get("tile_height_hint", 0), f"layers[{index}].tile_height_hint"),
                "tile_width_hint": _require_int(layer.get("tile_width_hint", 0), f"layers[{index}].tile_width_hint"),
            }
        )
        current_name = output_name

    input_tensor = tensor_meta[0]
    if input_quant_profile not in quant_profiles:
        input_shift = _require_int(
            input_spec.get("quant_shift", 0), "input.quant_shift"
        )
        input_quant_id = quantization_for(input_quant_profile, input_shift)
    else:
        input_quant_id = quant_profiles[input_quant_profile][0]
        if "quant_shift" in input_spec:
            quantization_for(
                input_quant_profile,
                _require_int(input_spec["quant_shift"], "input.quant_shift"),
            )
    input_tensor["quantization_id"] = input_quant_id

    for layer in compiled_layers:
        residual = layer["residual"]
        if residual is not None and residual["quantization_id"] != layer["quantization_id"]:
            raise CompilerError(
                f"layer {layer['name']!r} residual tensor quantization is incompatible with output"
            )

    tensor_allocations: list[dict[str, int]] = []
    last_layer = len(compiled_layers) - 1
    for tensor in tensor_meta:
        lifetime_begin = 0 if tensor["tensor_id"] == 0 else tensor["producer"]
        if tensor["flags"] & TensorFlags.MODEL_OUTPUT:
            lifetime_end = len(compiled_layers)
        elif tensor["consumers"]:
            lifetime_end = max(tensor["consumers"])
        else:
            lifetime_end = lifetime_begin
        pixel_stride = tensor["channels"]
        row_stride = tensor["width"] * pixel_stride
        allocation_size = tensor["height"] * row_stride
        allocation = {
            "tensor_id": tensor["tensor_id"],
            "allocation_size": allocation_size,
            "lifetime_begin": lifetime_begin,
            "lifetime_end": lifetime_end,
            "ddr_offset": 0,
        }
        tensor["allocation"] = allocation
        tensor["pixel_stride"] = pixel_stride
        tensor["row_stride"] = row_stride
        tensor_allocations.append(allocation)
    workspace_size = _allocate_workspace(tensor_allocations)

    layer_table_offset = MODEL_HEADER_SIZE
    tensor_table_offset = align_up(
        layer_table_offset + len(compiled_layers) * LAYER_DESCRIPTOR_SIZE,
        RECORD_ALIGNMENT,
    )
    quant_table_offset = align_up(
        tensor_table_offset + len(tensor_meta) * TENSOR_DESCRIPTOR_SIZE,
        RECORD_ALIGNMENT,
    )
    parameter_data_offset = align_up(
        quant_table_offset + len(quantizations) * QUANT_DESCRIPTOR_SIZE,
        RECORD_ALIGNMENT,
    )

    cursor = parameter_data_offset
    for layer in compiled_layers:
        cursor = align_up(cursor, 64)
        layer["weight_offset"] = cursor
        cursor += len(layer["weight_bytes"])
        if layer["bias_bytes"]:
            cursor = align_up(cursor, 4)
            layer["bias_offset"] = cursor
            cursor += len(layer["bias_bytes"])
        else:
            layer["bias_offset"] = 0
    package_size = align_up(cursor, RECORD_ALIGNMENT)

    layer_descriptors = []
    for index, layer in enumerate(compiled_layers):
        pad_top, pad_bottom, pad_left, pad_right = layer["padding"]
        flags = LayerFlags.BIAS_ENABLE if layer["bias_enable"] else LayerFlags(0)
        if index == last_layer:
            flags |= LayerFlags.LAST_LAYER
        layer_descriptors.append(
            LayerDescriptor(
                layer_id=index,
                input_tensor_id=layer["input"]["tensor_id"],
                output_tensor_id=layer["output"]["tensor_id"],
                residual_tensor_id=(
                    layer["residual"]["tensor_id"] if layer["residual"] is not None
                    else NO_TENSOR_ID
                ),
                quantization_id=layer["quantization_id"],
                weight_offset=layer["weight_offset"],
                weight_size=len(layer["weight_bytes"]),
                bias_offset=layer["bias_offset"],
                bias_size=len(layer["bias_bytes"]),
                parameter_crc32=parameter_crc32(layer["weight_bytes"], layer["bias_bytes"]),
                kernel_height=layer["kernel"], kernel_width=layer["kernel"],
                stride_y=layer["stride_y"], stride_x=layer["stride_x"],
                padding_top=pad_top, padding_bottom=pad_bottom,
                padding_left=pad_left, padding_right=pad_right,
                activation=layer["activation"], residual_mode=layer["residual_mode"],
                tile_height_hint=layer["tile_height_hint"],
                tile_width_hint=layer["tile_width_hint"], flags=flags,
            )
        )

    tensor_descriptors = []
    for tensor in tensor_meta:
        allocation = tensor["allocation"]
        tensor_descriptors.append(
            TensorDescriptor(
                tensor_id=tensor["tensor_id"],
                ddr_offset=allocation["ddr_offset"],
                allocation_size=allocation["allocation_size"],
                width=tensor["width"], height=tensor["height"],
                channels=tensor["channels"],
                quantization_id=tensor["quantization_id"],
                lifetime_begin=allocation["lifetime_begin"],
                lifetime_end=allocation["lifetime_end"],
                row_stride=tensor["row_stride"], pixel_stride=tensor["pixel_stride"],
                flags=tensor["flags"],
            )
        )

    header = ModelHeader(
        package_size=package_size, model_id=model_id,
        model_generation_id=generation_id,
        layer_count=len(layer_descriptors), tensor_count=len(tensor_descriptors),
        quantization_count=len(quantizations),
        layer_table_offset=layer_table_offset,
        tensor_table_offset=tensor_table_offset,
        quantization_table_offset=quant_table_offset,
        parameter_data_offset=parameter_data_offset,
        parameter_data_size=package_size - parameter_data_offset,
        input_tensor_id=0, output_tensor_id=tensor_meta[-1]["tensor_id"],
        workspace_size=workspace_size,
    )
    validate_model(header, layer_descriptors, tensor_descriptors, quantizations)

    package = bytearray(package_size)
    package[:MODEL_HEADER_SIZE] = header.pack()
    for index, descriptor in enumerate(layer_descriptors):
        start = layer_table_offset + index * LAYER_DESCRIPTOR_SIZE
        package[start:start + LAYER_DESCRIPTOR_SIZE] = descriptor.pack()
    for index, descriptor in enumerate(tensor_descriptors):
        start = tensor_table_offset + index * TENSOR_DESCRIPTOR_SIZE
        package[start:start + TENSOR_DESCRIPTOR_SIZE] = descriptor.pack()
    for index, descriptor in enumerate(quantizations):
        start = quant_table_offset + index * QUANT_DESCRIPTOR_SIZE
        package[start:start + QUANT_DESCRIPTOR_SIZE] = descriptor.pack()
    for layer in compiled_layers:
        start = layer["weight_offset"]
        package[start:start + len(layer["weight_bytes"])] = layer["weight_bytes"]
        if layer["bias_bytes"]:
            start = layer["bias_offset"]
            package[start:start + len(layer["bias_bytes"])] = layer["bias_bytes"]

    header = dataclasses.replace(header, package_sha256=compute_package_sha256(package))
    package[:MODEL_HEADER_SIZE] = header.pack()
    header = dataclasses.replace(header, package_crc32=compute_package_crc32(package))
    package[:MODEL_HEADER_SIZE] = header.pack()
    parse_model_package(bytes(package))
    return bytes(package)


def package_summary(package: bytes) -> dict[str, Any]:
    header, layers, tensors, quantizations = parse_model_package(package)
    return {
        "abi_version": 1,
        "model_id": header.model_id,
        "model_generation_id": header.model_generation_id,
        "package_size": header.package_size,
        "workspace_size": header.workspace_size,
        "package_sha256": header.package_sha256.hex(),
        "package_crc32": f"0x{header.package_crc32:08x}",
        "layer_count": len(layers),
        "tensor_count": len(tensors),
        "quantization_count": len(quantizations),
        "layers": [
            {
                "layer_id": layer.layer_id,
                "input_tensor_id": layer.input_tensor_id,
                "output_tensor_id": layer.output_tensor_id,
                "kernel": [layer.kernel_height, layer.kernel_width],
                "stride": [layer.stride_y, layer.stride_x],
                "padding": [layer.padding_top, layer.padding_bottom,
                            layer.padding_left, layer.padding_right],
                "weight_bytes": layer.weight_size,
                "bias_bytes": layer.bias_size,
                "quantization_id": layer.quantization_id,
                "residual_mode": layer.residual_mode.name.lower(),
            }
            for layer in layers
        ],
        "tensors": [
            {
                "tensor_id": tensor.tensor_id,
                "shape_nhwc": [1, tensor.height, tensor.width, tensor.channels],
                "ddr_offset": tensor.ddr_offset,
                "allocation_size": tensor.allocation_size,
                "lifetime": [tensor.lifetime_begin, tensor.lifetime_end],
                "quantization_id": tensor.quantization_id,
            }
            for tensor in tensors
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("spec", type=Path, help="V1 model specification JSON")
    parser.add_argument("-o", "--output", type=Path, required=True, help="Output .cnn package")
    parser.add_argument("--summary", type=Path, help="Optional JSON package summary")
    args = parser.parse_args()

    spec = json.loads(args.spec.read_text(encoding="utf-8"))
    package = compile_model(spec, base_dir=args.spec.parent)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(package)
    summary = package_summary(package)
    if args.summary:
        args.summary.parent.mkdir(parents=True, exist_ok=True)
        args.summary.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(
        f"Wrote {args.output} ({len(package)} bytes, "
        f"SHA-256 {summary['package_sha256']})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
