# V1 Model Compiler and Package Executor

## Scope

Phase 2 provides a dependency-free compiler from a human-readable JSON model
description to the frozen V1 binary package ABI. It also provides an
independent bit-accurate executor that parses and validates the serialized
package before running it. Neither tool relies on the current fixed
three-layer descriptor ROM.

This is the software reference path for the upcoming runtime metadata and
descriptor-driven RTL. It does not yet make the board-facing RTL
layer-programmable.

## Compile and Execute

Build the checked-in RGB identity example:

```bash
make model-package-example
```

The target writes:

```text
build/models/rgb_identity.cnn
build/models/rgb_identity.summary.json
build/models/rgb_identity.output.json
```

The equivalent commands are:

```bash
python3 models/model_compiler.py \
  examples/models/rgb_identity.json \
  -o build/models/rgb_identity.cnn \
  --summary build/models/rgb_identity.summary.json

python3 models/package_executor.py \
  build/models/rgb_identity.cnn \
  examples/tensors/rgb_4x4.json \
  -o build/models/rgb_identity.output.json
```

The executor verifies package SHA-256, package CRC32, every layer parameter
CRC32, all descriptor semantics, and the input tensor shape before execution.

## Source Schema

The top-level JSON object is:

```json
{
  "format": "cnn-accelerator-model-v1",
  "model_id": 42,
  "model_generation_id": 3,
  "input": {
    "name": "input",
    "width": 224,
    "height": 224,
    "channels": 3
  },
  "layers": []
}
```

| Field | Required | Meaning |
|---|---|---|
| `format` | yes | Exactly `cnn-accelerator-model-v1` |
| `model_id` | yes | Stable unsigned model identity |
| `model_generation_id` | no | Software-managed model generation, default zero |
| `input` | yes | Model input tensor declaration |
| `layers` | yes | One to eight sequential convolution layers |

The input object accepts `name`, `width`, `height`, `channels`, and optional
`quantization_profile`, `quant_multiplier`/`quant_multipliers`, and
`quant_shift`/`quant_shifts`. Batch is fixed at one and tensor
layout is NHWC.

### Layer Fields

| Field | Required | V1 behavior |
|---|---|---|
| `name` | no | Diagnostic name; defaults to the layer index |
| `output` | no | Output tensor name |
| `output_channels` | yes | 1-16 |
| `kernel_size` | no | 1 or 3; default 3 |
| `stride` | no | Scalar or `[y, x]`, each 1 or 2 |
| `padding` | no | Scalar, `[top,bottom,left,right]`, or named object |
| `activation` | no | `none` or `relu` |
| `quant_multiplier` | no | Positive INT32 expanded across output channels; default 1 |
| `quant_multipliers` | no | Positive INT32 value per output channel |
| `quant_shift` | no | Shift 0-62 expanded across output channels; default 0 |
| `quant_shifts` | no | Shift 0-62 per output channel |
| `quantization_profile` | no | Named compatibility domain for residual tensors |
| `bias_enable` | no | Boolean, default true |
| `weights` / `weights_file` | yes | Exactly one weight source |
| `bias` / `bias_file` | no | Defaults to zero when bias is enabled |
| `residual` | conditional | Name of an earlier tensor |
| `residual_mode` | no | `none`, `add`, `subtract`, or `sub` |
| `tile_height_hint` | no | Zero lets future runtime hardware choose |
| `tile_width_hint` | no | Zero lets future runtime hardware choose |

Layers form a sequential main path. Residual references may point to the model
input or any earlier named tensor. General graph scheduling, concatenation,
pooling, dilation, groups, and depthwise convolution are outside V1.

### Parameter Encodings

Inline weights may be a flat array or nested OIHW arrays. Their flattened order
must be:

```text
output channel -> input channel -> kernel y -> kernel x
```

Inline biases are signed INT32 arrays indexed by output channel. Parameter
files are resolved relative to the model JSON and support:

- `.json`: flat or nested integer arrays
- weight `.bin`: packed signed INT8 OIHW bytes
- bias `.bin`: packed little-endian signed INT32 values

The compiler checks exact element counts and signed ranges. It inserts alignment
padding into the package but excludes padding from parameter CRC calculations.

## Quantization Profiles

Every layer output receives a quantization descriptor. A named
`quantization_profile` lets tensors declare that they occupy the same numeric
domain. Reusing a profile with different channel counts, multipliers, or shifts
is rejected in V1.

When a layer uses the model input as a residual source and does not name a
profile explicitly, its output automatically uses the input profile. This
models the current denoiser correctly: convolution output is shifted to the
input image's INT8 domain before `input - predicted_noise` is evaluated.

V1 uses symmetric per-output-channel fixed-point requantization. The output
zero point is zero and every channel carries its own positive INT32 multiplier
and shift. Scalar fields are expanded to all output channels. Rounding is
always round-half-to-even.

## Compiler Outputs

The compiler deterministically:

1. Resolves tensor shapes and validates layer geometry.
2. Assigns layer, tensor, and quantization IDs.
3. Computes inclusive tensor lifetimes.
4. Reuses 64-byte-aligned DDR workspace regions when lifetimes do not overlap.
5. Packs OIHW INT8 weights and little-endian INT32 biases.
6. Builds aligned descriptor tables and package-relative parameter offsets.
7. Computes layer CRC32 values, package SHA-256, and package CRC32.
8. Parses and validates its own emitted package before returning it.

Compilation is deterministic: identical source values and parameter bytes
produce an identical package and digest.

The optional summary JSON records package identity, sizes, layer geometry,
parameter lengths, tensor shapes, workspace offsets, lifetimes, and
quantization references without duplicating the binary package as an execution
input.

## Bit-Accurate Execution

`models/package_executor.py` executes only information recovered from the
binary package. It supports all V1 convolution geometry, including independent
axis stride and asymmetric per-edge padding, and follows this arithmetic order:

```text
INT8 convolution -> INT32 bias -> optional ReLU
  -> per-channel INT32 multiply -> round-half-to-even shift -> INT8 saturation
  -> optional post-quant residual -> INT8 saturation
```

The package executor is the golden behavioral oracle for descriptor-driven RTL
and future runtime software. Spatial tiling may change execution order in RTL,
but it must not change these element results.

## Verification

`make model-test` covers:

- mixed 1x1 and 3x3 package execution against the existing arithmetic model
- per-output-channel multiplier/shift serialization and execution
- the complete default Gaussian network with input residual subtraction
- asymmetric padding driven by serialized descriptors
- raw binary and JSON parameter files
- deterministic compilation and package summaries
- lifetime-aware DDR workspace reuse
- malformed dimensions, parameters, booleans, residuals, checksums, and ABI data

The full existing RTL regression remains available through `make regression`.
