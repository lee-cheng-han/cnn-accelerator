# V2 Image-to-Image CNN Architecture

## Status

The current board-facing accelerator is the v1 Zynq DMA design. It is intentionally preserved as the first hardware bring-up target.

The v2 path is a new experimental architecture for a tiled image-to-image CNN accelerator. It starts with independent compute modules under `rtl/compute_v2` and separate tests under the `v2-unit` make target, so existing v1 regressions and board artifacts are not disturbed.

## Target Network

Initial application: RGB image denoising.

```text
Input RGB tensor
  -> Conv 3x3,  3 -> 16, padding 1, ReLU
  -> Conv 3x3, 16 -> 16, padding 1, ReLU
  -> Conv 3x3, 16 ->  3, padding 1
  -> optional residual reconstruction
  -> Output RGB tensor
```

## Compute Core Parameters

The first v2 compute slice uses:

```systemverilog
parameter int PC = 4;  // parallel input-channel lanes
parameter int PK = 8;  // parallel output-channel lanes
```

This gives 32 signed INT8 multiplications per compute issue:

```text
4 input lanes x 8 output lanes = 32 multiplies/cycle
```

## Implemented Phases

Phase B/Chunk 1 foundation is present:

| Module | Purpose |
|---|---|
| `reduction_tree` | Pipelined signed reduction of one output lane's products |
| `parallel_mac_array` | PC x PK signed INT8 multiply array with PK dot-product outputs |
| `psum_accumulator` | PK-lane INT32 partial-sum accumulator with output-lane masking |
| `tail_mask_generator` | Runtime tail masks for non-divisible input/output channel tiles |
| `parallel_bias_add` | PK-lane INT32 bias add |
| `parallel_relu` | PK-lane ReLU |
| `parallel_quantizer` | PK-lane arithmetic right-shift quantization |
| `parallel_saturate` | PK-lane signed INT8 saturation |
| `residual_add` | Optional signed residual add/subtract helper |

The first Chunk 2 milestone is also present:

| Module | Purpose |
|---|---|
| `tiled_conv1x1_engine` | Single-pixel 1x1 layer engine with runtime `Cin`, runtime `Cout`, PC/PK tiling, tail masks, bias, ReLU, quantization, and saturation |

The first Chunk 3 milestone is present:

| Module | Purpose |
|---|---|
| `tensor_address_gen` | Converts output coordinate, kernel tap, stride, and padding into a valid input pixel index |
| `tiled_conv3x3_engine` | Single-output-position 3x3 layer engine with runtime `Cin`, runtime `Cout`, PC/PK tiling, zero padding, stride 1/2 support, tail masks, bias, ReLU, quantization, and saturation |

Chunks 4-6 have simulation-focused first milestones:

| Module | Purpose |
|---|---|
| `activation_scratchpad` | Local activation memory with scalar load/debug access and PC-lane vector reads |
| `weight_scratchpad` | Local weight memory with scalar load/debug access and PK x PC matrix reads for the MAC array |
| `single_layer_scheduler` | Full-image single-layer scheduler that walks output `x/y`, starts one reusable 1x1 or 3x3 engine per output position, and writes an output tensor |
| `denoise_layer_descriptor_rom` | Hardware-readable descriptors for the planned 3-layer RGB denoising network: `3 -> 16`, `16 -> 16`, `16 -> 3` |

Current v2 scope remains intentionally pre-board and simulation-first. The scheduler proves full-image loop control against local arrays; DMA tensor movement, ping-pong buffering, and AXI-facing v2 integration are still future work.

The v2 Python reference model is present in `models/image2image_int8.py`. It is dependency-free and models the exact integer arithmetic used by the RTL path:

- signed INT8 input tensors and weights
- INT32 accumulation
- optional bias add
- ReLU before quantization
- arithmetic right shift quantization
- signed INT8 saturation
- optional residual add/subtract, including the denoising form `output = input - predicted_noise`

The golden tensor flow is also present. `models/generate_v2_golden_tensors.py` writes deterministic input, weight, bias, config, and expected-output memories under `build/v2_golden`; `tb_v2_golden_tensor_flow` loads those files into RTL and compares the scheduler output bit-for-bit against the Python model.

Run:

```bash
make v2-model-test
make v2-golden-test
make v2-unit
```

## Preserved V1 Flow

The v1 flow remains the required first-board milestone:

```bash
make preboard-proof
make program-arty-z7-dma
```

Expected board result:

```text
[PASS] CNN DMA accelerator test passed
```

## Next V2 Milestones

1. Extend golden tensor tests from single-layer fixtures to the full 3-layer denoising network.
2. Connect the scratchpad interfaces to explicit tensor load/store controllers.
3. Add ping-pong activation and weight buffering so load and compute can overlap.
4. Add a multi-layer job controller that sequences the three denoising descriptors.
5. Connect the v2 scheduler to an AXI-facing top-level wrapper after the offline model and unit tests are stable.
6. Add v2 performance counters and synthesis experiments for `PC/PK` scaling.
