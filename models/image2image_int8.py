"""Dependency-free bit-accurate model for the image-to-image CNN path.

Tensor layout is NHWC: height x width x channels.
Weight layout is OIHW: output channels x input channels x kernel y x kernel x.
All tensor values are represented as Python integers in signed INT8 range.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, Literal, Sequence


ResidualMode = Literal["none", "add", "sub"]
RoundingMode = Literal["arithmetic_shift", "round_half_to_even"]
Tensor3D = list[list[list[int]]]
Weights4D = list[list[list[list[int]]]]


DEFAULT_DENOISE_QUANT_SHIFTS = (0, 5, 1)

# Eight signed feature pairs fill the 16-channel hidden tensors. Repeated color
# bases keep every channel active while preserving signed INT8 values through
# ReLU without requiring a wider activation format.
DEFAULT_COLOR_FEATURES = (0, 0, 0, 1, 1, 1, 2, 2)
DEFAULT_COLOR_COEFFICIENTS = (1, 2, -1, 1, 2, -1, 1, 1)

# 16 * (identity - Gaussian[1 2 1; 2 4 2; 1 2 1] / 16).
DEFAULT_HIGHPASS_KERNEL = (
    (-1, -2, -1),
    (-2, 12, -2),
    (-1, -2, -1),
)


@dataclass(frozen=True)
class LayerConfig:
    input_channels: int
    output_channels: int
    kernel_size: int = 3
    stride: int = 1
    padding: int = 1
    bias_enable: bool = True
    relu_enable: bool = True
    quant_enable: bool = True
    quant_multiplier: int = 1
    quant_shift: int = 0
    rounding_mode: RoundingMode = "arithmetic_shift"
    residual_mode: ResidualMode = "none"


def saturate_int8(value: int) -> int:
    return max(-128, min(127, int(value)))


def arithmetic_shift_right(value: int, shift: int) -> int:
    if shift < 0 or shift > 31:
        raise ValueError(f"quant_shift must be in range 0..31, got {shift}")
    return int(value) >> int(shift)


def round_half_to_even_shift(value: int, shift: int) -> int:
    """Divide by 2**shift using deterministic ties-to-even rounding."""
    if shift < 0 or shift > 62:
        raise ValueError(f"quant_shift must be in range 0..62, got {shift}")
    if shift == 0:
        return int(value)
    magnitude = abs(int(value))
    quotient, remainder = divmod(magnitude, 1 << shift)
    half = 1 << (shift - 1)
    if remainder > half or (remainder == half and quotient & 1):
        quotient += 1
    return -quotient if value < 0 else quotient


def requantize_int32(
    value: int,
    multiplier: int,
    shift: int,
    output_zero_point: int = 0,
) -> int:
    """Apply final V1 per-channel fixed-point requantization."""
    if multiplier <= 0 or multiplier > 0x7FFF_FFFF:
        raise ValueError("quant_multiplier must be a positive signed INT32 value")
    if output_zero_point != 0:
        raise ValueError("V1 requires symmetric output_zero_point=0")
    scaled = round_half_to_even_shift(int(value) * int(multiplier), shift)
    return saturate_int8(scaled + output_zero_point)


def postprocess_accumulator(
    acc: int,
    bias: int = 0,
    *,
    bias_enable: bool = True,
    relu_enable: bool = True,
    quant_enable: bool = True,
    quant_multiplier: int = 1,
    quant_shift: int = 0,
    rounding_mode: RoundingMode = "arithmetic_shift",
) -> int:
    value = int(acc)

    if bias_enable:
        value += int(bias)

    if relu_enable and value < 0:
        value = 0

    if quant_enable:
        if rounding_mode == "arithmetic_shift":
            value = arithmetic_shift_right(value * quant_multiplier, quant_shift)
        elif rounding_mode == "round_half_to_even":
            return requantize_int32(value, quant_multiplier, quant_shift)
        else:
            raise ValueError(f"unsupported rounding_mode {rounding_mode!r}")

    return saturate_int8(value)


def tensor_shape_hwc(x: Sequence[Sequence[Sequence[int]]]) -> tuple[int, int, int]:
    h = len(x)
    if h == 0:
        raise ValueError("input tensor height must be positive")
    w = len(x[0])
    if w == 0:
        raise ValueError("input tensor width must be positive")
    c = len(x[0][0])
    if c == 0:
        raise ValueError("input tensor channels must be positive")

    for row in x:
        if len(row) != w:
            raise ValueError("input tensor rows have inconsistent widths")
        for pixel in row:
            if len(pixel) != c:
                raise ValueError("input tensor pixels have inconsistent channel counts")

    return h, w, c


def weights_shape_oihw(weights: Sequence[Sequence[Sequence[Sequence[int]]]]) -> tuple[int, int, int, int]:
    oc = len(weights)
    if oc == 0:
        raise ValueError("weights output channels must be positive")
    ic = len(weights[0])
    if ic == 0:
        raise ValueError("weights input channels must be positive")
    kh = len(weights[0][0])
    if kh == 0:
        raise ValueError("weights kernel height must be positive")
    kw = len(weights[0][0][0])
    if kw == 0:
        raise ValueError("weights kernel width must be positive")

    for out_channel in weights:
        if len(out_channel) != ic:
            raise ValueError("weights have inconsistent input-channel counts")
        for in_channel in out_channel:
            if len(in_channel) != kh:
                raise ValueError("weights have inconsistent kernel heights")
            for row in in_channel:
                if len(row) != kw:
                    raise ValueError("weights have inconsistent kernel widths")

    return oc, ic, kh, kw


def zeros_hwc(height: int, width: int, channels: int) -> Tensor3D:
    return [[[0 for _ in range(channels)] for _ in range(width)] for _ in range(height)]


def copy_int8_tensor(x: Sequence[Sequence[Sequence[int]]]) -> Tensor3D:
    return [[[saturate_int8(value) for value in pixel] for pixel in row] for row in x]


def _validate_conv_args(
    x: Sequence[Sequence[Sequence[int]]],
    weights: Sequence[Sequence[Sequence[Sequence[int]]]],
    bias: Sequence[int],
    cfg: LayerConfig,
) -> tuple[int, int, int]:
    if cfg.kernel_size not in (1, 3):
        raise ValueError(f"kernel_size must be 1 or 3, got {cfg.kernel_size}")
    if cfg.stride not in (1, 2):
        raise ValueError(f"stride must be 1 or 2, got {cfg.stride}")
    if cfg.padding not in (0, 1):
        raise ValueError(f"padding must be 0 or 1, got {cfg.padding}")
    if cfg.input_channels < 1 or cfg.output_channels < 1:
        raise ValueError("input_channels and output_channels must be positive")
    max_shift = 62 if cfg.rounding_mode == "round_half_to_even" else 31
    if cfg.quant_shift < 0 or cfg.quant_shift > max_shift:
        raise ValueError(f"quant_shift must be in range 0..{max_shift}, got {cfg.quant_shift}")
    if cfg.quant_multiplier <= 0 or cfg.quant_multiplier > 0x7FFF_FFFF:
        raise ValueError("quant_multiplier must be a positive signed INT32 value")

    in_h, in_w, channels = tensor_shape_hwc(x)
    weight_oc, weight_ic, weight_kh, weight_kw = weights_shape_oihw(weights)

    if channels < cfg.input_channels:
        raise ValueError(
            f"input tensor has {channels} channels, descriptor requires {cfg.input_channels}"
        )
    if (weight_oc, weight_ic, weight_kh, weight_kw) != (
        cfg.output_channels,
        cfg.input_channels,
        cfg.kernel_size,
        cfg.kernel_size,
    ):
        raise ValueError(
            "weights must have shape "
            f"({cfg.output_channels}, {cfg.input_channels}, "
            f"{cfg.kernel_size}, {cfg.kernel_size}), got "
            f"({weight_oc}, {weight_ic}, {weight_kh}, {weight_kw})"
        )
    if len(bias) != cfg.output_channels:
        raise ValueError(f"bias must have {cfg.output_channels} entries, got {len(bias)}")

    return in_h, in_w, channels


def conv2d_layer_int8(
    x: Sequence[Sequence[Sequence[int]]],
    weights: Sequence[Sequence[Sequence[Sequence[int]]]],
    bias: Sequence[int],
    cfg: LayerConfig,
) -> Tensor3D:
    """Run one quantized convolution layer and return a signed INT8 NHWC tensor."""

    in_h, in_w, _ = _validate_conv_args(x, weights, bias, cfg)
    out_h = ((in_h + (2 * cfg.padding) - cfg.kernel_size) // cfg.stride) + 1
    out_w = ((in_w + (2 * cfg.padding) - cfg.kernel_size) // cfg.stride) + 1

    if out_h <= 0 or out_w <= 0:
        raise ValueError(
            f"invalid output shape {out_h}x{out_w} from input {in_h}x{in_w}, "
            f"kernel={cfg.kernel_size}, stride={cfg.stride}, padding={cfg.padding}"
        )

    y = zeros_hwc(out_h, out_w, cfg.output_channels)

    for oy in range(out_h):
        for ox in range(out_w):
            for co in range(cfg.output_channels):
                acc = 0

                for ky in range(cfg.kernel_size):
                    for kx in range(cfg.kernel_size):
                        iy = (oy * cfg.stride) + ky - cfg.padding
                        ix = (ox * cfg.stride) + kx - cfg.padding

                        if iy < 0 or ix < 0 or iy >= in_h or ix >= in_w:
                            continue

                        for ci in range(cfg.input_channels):
                            acc += int(x[iy][ix][ci]) * int(weights[co][ci][ky][kx])

                y[oy][ox][co] = postprocess_accumulator(
                    acc,
                    int(bias[co]),
                    bias_enable=cfg.bias_enable,
                    relu_enable=cfg.relu_enable,
                    quant_enable=cfg.quant_enable,
                    quant_multiplier=cfg.quant_multiplier,
                    quant_shift=cfg.quant_shift,
                    rounding_mode=cfg.rounding_mode,
                )

    return y


def apply_residual(
    base: Sequence[Sequence[Sequence[int]]],
    update: Sequence[Sequence[Sequence[int]]],
    mode: ResidualMode,
) -> Tensor3D:
    if mode == "none":
        return copy_int8_tensor(update)
    if mode not in ("add", "sub"):
        raise ValueError(f"unsupported residual mode {mode!r}")

    base_h, base_w, base_c = tensor_shape_hwc(base)
    update_h, update_w, update_c = tensor_shape_hwc(update)
    if (base_h, base_w, base_c) != (update_h, update_w, update_c):
        raise ValueError(
            f"residual shape mismatch: base {(base_h, base_w, base_c)}, "
            f"update {(update_h, update_w, update_c)}"
        )

    out = zeros_hwc(update_h, update_w, update_c)
    for y in range(update_h):
        for x in range(update_w):
            for c in range(update_c):
                if mode == "add":
                    value = int(base[y][x][c]) + int(update[y][x][c])
                else:
                    value = int(base[y][x][c]) - int(update[y][x][c])
                out[y][x][c] = saturate_int8(value)

    return out


def run_layers_int8(
    x: Sequence[Sequence[Sequence[int]]],
    layers: Iterable[tuple[LayerConfig, Weights4D, Sequence[int]]],
) -> Tensor3D:
    """Run a sequence of layers.

    If a layer's residual mode is enabled, the residual source is the original
    network input. This matches the initial denoising use case where the final
    layer predicts noise and output = input - predicted_noise.
    """

    original = copy_int8_tensor(x)
    current = original

    for cfg, weights, bias in layers:
        conv_out = conv2d_layer_int8(current, weights, bias, cfg)
        if cfg.residual_mode == "none":
            current = conv_out
        else:
            current = apply_residual(original, conv_out, cfg.residual_mode)

    return current


def make_denoise_layer_configs(
    *,
    quant_shifts: tuple[int, int, int] = (0, 0, 0),
    final_residual: bool = True,
) -> tuple[LayerConfig, LayerConfig, LayerConfig]:
    return (
        LayerConfig(
            input_channels=3,
            output_channels=16,
            kernel_size=3,
            stride=1,
            padding=1,
            relu_enable=True,
            quant_shift=quant_shifts[0],
        ),
        LayerConfig(
            input_channels=16,
            output_channels=16,
            kernel_size=3,
            stride=1,
            padding=1,
            relu_enable=True,
            quant_shift=quant_shifts[1],
        ),
        LayerConfig(
            input_channels=16,
            output_channels=3,
            kernel_size=3,
            stride=1,
            padding=1,
            relu_enable=False,
            quant_shift=quant_shifts[2],
            residual_mode="sub" if final_residual else "none",
        ),
    )


def _zero_weights(cout: int, cin: int, kernel_size: int = 3) -> Weights4D:
    return [
        [
            [[0 for _ in range(kernel_size)] for _ in range(kernel_size)]
            for _ in range(cin)
        ]
        for _ in range(cout)
    ]


def make_default_denoise_parameters() -> tuple[
    tuple[Weights4D, list[int]],
    tuple[Weights4D, list[int]],
    tuple[Weights4D, list[int]],
]:
    """Return deterministic weights for the default RGB Gaussian denoiser.

    Layer 0 encodes eight signed RGB feature pairs. Layer 1 converts each pair
    into a signed high-frequency feature using ``DEFAULT_HIGHPASS_KERNEL``.
    Layer 2 reconstructs one predicted-noise channel per RGB component. With
    final residual subtraction enabled, the network output is a 3x3 Gaussian
    low-pass image (subject to INT8 saturation and zero padding at boundaries).
    """

    hidden_channels = len(DEFAULT_COLOR_FEATURES) * 2
    layer0 = _zero_weights(hidden_channels, 3)
    layer1 = _zero_weights(hidden_channels, hidden_channels)
    layer2 = _zero_weights(3, hidden_channels)

    for feature, color in enumerate(DEFAULT_COLOR_FEATURES):
        positive = feature * 2
        negative = positive + 1
        layer0[positive][color][1][1] = 1
        layer0[negative][color][1][1] = -1

    for output_feature, output_color in enumerate(DEFAULT_COLOR_FEATURES):
        output_positive = output_feature * 2
        output_negative = output_positive + 1

        for input_feature, input_color in enumerate(DEFAULT_COLOR_FEATURES):
            if input_color != output_color:
                continue

            coefficient = DEFAULT_COLOR_COEFFICIENTS[input_feature]
            input_positive = input_feature * 2
            input_negative = input_positive + 1

            for ky in range(3):
                for kx in range(3):
                    tap = coefficient * DEFAULT_HIGHPASS_KERNEL[ky][kx]
                    layer1[output_positive][input_positive][ky][kx] = tap
                    layer1[output_positive][input_negative][ky][kx] = -tap
                    layer1[output_negative][input_positive][ky][kx] = -tap
                    layer1[output_negative][input_negative][ky][kx] = tap

    for color in range(3):
        for feature, feature_color in enumerate(DEFAULT_COLOR_FEATURES):
            if feature_color != color:
                continue

            coefficient = DEFAULT_COLOR_COEFFICIENTS[feature]
            positive = feature * 2
            negative = positive + 1
            layer2[color][positive][1][1] = coefficient
            layer2[color][negative][1][1] = -coefficient

    return (
        (layer0, [0 for _ in range(hidden_channels)]),
        (layer1, [0 for _ in range(hidden_channels)]),
        (layer2, [0 for _ in range(3)]),
    )
