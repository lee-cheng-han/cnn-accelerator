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
| `ping_pong_bank_controller` | Tracks two memory banks through load, valid, compute, release, overlap, and illegal-request states |
| `ping_pong_activation_scratchpad` | Two activation scratchpad banks with independent load-bank and compute-bank selection |
| `ping_pong_weight_scratchpad` | Two weight scratchpad banks with independent load-bank and compute-bank selection |
| `activation_tensor_load_controller` | Streams activation values into `activation_scratchpad` in pixel-major, channel-minor order with valid/ready backpressure |
| `weight_tensor_load_controller` | Streams 1x1 or 3x3 weights into `weight_scratchpad` in output-channel, input-channel, kernel-tap order |
| `output_tensor_store_controller` | Streams computed output tensor values out in pixel-major, channel-minor order with valid/ready backpressure and final-word `last` signaling |
| `single_layer_scheduler` | Full-image single-layer scheduler that walks output `x/y`, starts one reusable 1x1 or 3x3 engine per output position, and writes an output tensor |
| `denoise_layer_descriptor_rom` | Hardware-readable descriptors for the planned 3-layer RGB denoising network: `3 -> 16`, `16 -> 16`, `16 -> 3` |
| `multi_layer_job_controller` | Sequences the three denoising descriptors through one reusable scheduler, alternates two intermediate activation banks, gates each layer on parameter readiness, and optionally performs final residual subtraction |
| `stream_loaded_multi_layer_job_controller` | Loads layer 0, starts compute, prefetches layer 1/2 parameters while compute is active, and streams final RGB output with backpressure |
| `v2_tensor_packet_router` | Converts one 32-bit AXI input stream into ordered activation, bias, and weight streams while validating headers, lengths, and `TLAST` |
| `cnn_image2image_axi_stream_top` | Connects the packet router, multi-layer scheduler stack, and sign-extended 32-bit AXI output stream with job status and protocol errors |
| `v2_performance_counters` | Captures job, packet, compute, prefetch, layer, transfer, and backpressure cycles for the most recently started job |

Current v2 scope remains intentionally pre-board and simulation-first. The schedulers prove full-image and multi-layer loop control, while the stream-loaded wrapper proves the first end-to-end activation/weight/bias load, overlapped parameter prefetch, compute, and output-store path around local memories. Intermediate layer results alternate between feature bank 0 and feature bank 1. The scheduler will not launch a layer until its parameter-ready bit is set, so arbitrary input-stream stalls cannot expose partially loaded weights. The standalone ping-pong scratchpads and bank controller separately prove that a physical bank cannot be overwritten while compute owns it. The AXI-Stream top now proves a concrete packetized data-plane boundary, but it is not yet integrated into the Zynq block design or controlled by a v2 AXI-Lite register bank. The packet format is defined in [v2_stream_interface.md](v2_stream_interface.md).

The v2 Python reference model is present in `models/image2image_int8.py`. It is dependency-free and models the exact integer arithmetic used by the RTL path:

- signed INT8 input tensors and weights
- INT32 accumulation
- optional bias add
- ReLU before quantization
- arithmetic right shift quantization
- signed INT8 saturation
- optional residual add/subtract, including the denoising form `output = input - predicted_noise`

The golden tensor flow is also present. `models/generate_v2_golden_tensors.py` writes deterministic input, weight, bias, config, and expected-output memories under `build/v2_golden`; `tb_v2_golden_tensor_flow` loads single-layer fixtures into RTL and compares the scheduler output bit-for-bit against the Python model. `tb_v2_full_network_golden_flow` does the same for the full 3-layer denoising controller, including both final residual reconstruction and raw final-layer output. `tb_v2_stream_loaded_full_network_golden_flow` feeds those generated tensors through the stream-loaded wrapper and checks the streamed RGB output under backpressure.

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

The first `PC/PK` synthesis sweep is complete. The isolated compute slice meets the
125 MHz target for `2x8`, `4x4`, and `4x8`; see
[v2_synthesis_experiments.md](v2_synthesis_experiments.md). The remaining milestones
are:

1. Add a v2 AXI-Lite control/status register block and integrate the AXI-Stream top into a separate Vivado block design.
2. Replace full-frame simulation memories with bounded tile/line buffers before targeting large images.
3. Confirm the selected `PC=4`, `PK=8` configuration with full-design post-route timing.
