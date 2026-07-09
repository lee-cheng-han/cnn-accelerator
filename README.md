# Zynq CNN Accelerator

A SystemVerilog CNN accelerator for the Digilent Arty Z7-20 / Zynq-7000 platform. The programmable logic implements a small streaming CNN datapath; the ARM Cortex-A9 configures it through AXI-Lite and moves image/result data through AXI DMA.

The project is currently in the final pre-board stage: RTL simulation, Vivado implementation, XSA export, and Vitis bare-metal build are complete. Physical board validation is the next milestone when the Arty Z7-20 arrives.

## Results Snapshot

| Area | Status |
|---|---|
| RTL language | SystemVerilog |
| Target board | Digilent Arty Z7-20 |
| FPGA part | `xc7z020clg400-1` |
| Toolchain | Vivado / Vitis 2025.2 |
| Control interface | AXI-Lite |
| Data interface | AXI DMA + AXI-Stream |
| Input format | Packed RGB, `0x00BBGGRR` |
| CNN modes | True 1x1 and valid 3x3 convolution |
| Input / output channels | 3 input channels, 4 output channels |
| Data / weight / accumulator width | int8 / int8 / int32 |
| Timing | Met at 125 MHz |
| LUTs / registers | 6,692 LUTs / 8,058 registers |
| BRAM / DSP | 2 BRAM tiles / 1 DSP |
| DMA top simulation | Passing, 80 checked outputs |
| Bitstream / XSA / ELF | Built |
| Board validation | Pending hardware |

Expected board-level result:

```text
[PASS] CNN DMA accelerator test passed
```

## Why This Project Matters

This repository demonstrates a complete FPGA accelerator slice:

- Microarchitecture: streaming RGB input, 1x1/3x3 convolution, post-processing, output buffering.
- Integration: Zynq PS, AXI-Lite control, AXI DMA, AXI-Stream datapath, Vivado block design automation.
- Verification: unit tests, randomized datapath tests, AXI-Lite tests, DMA-style system simulation, generated golden vectors.
- Software: bare-metal C application that configures the accelerator, runs DMA transfers, and compares hardware output against golden data.
- Implementation: scripted Vivado project creation, bitstream generation, XSA export, and Vitis app build.

## Current Architecture

```text
ARM Cortex-A9
    |
    | AXI-Lite writes
    v
CNN config/status registers
    |
    | width, height, mode, weights, bias
    v
CNN accelerator core


DDR input buffer
    |
    | AXI memory-mapped read
    v
AXI DMA MM2S
    |
    | AXI-Stream packed RGB pixels, one beat = 0x00BBGGRR
    v
axis_rgb_to_channels
    |
    | channel-serial R, G, B samples
    v
streaming_cnn_core
    |
    | signed 8-bit CNN outputs
    v
axis_output_widen
    |
    | sign-extended 32-bit AXI-Stream words
    v
AXI DMA S2MM
    |
    | AXI memory-mapped write
    v
DDR output buffer
```

The active board-facing top is [rtl/zynq/cnn_dma_system_top.sv](rtl/zynq/cnn_dma_system_top.sv).

## Experimental V2 Image-to-Image Path

The repository now has a separate v2 compute path for the future tiled image-to-image CNN architecture. The v2 work is intentionally isolated from the board-ready v1 DMA flow.

Current v2 status:

- PC x PK signed INT8 MAC array foundation.
- Default target: `PC=4`, `PK=8`, 32 multiplies per compute issue.
- 8-lane INT32 partial-sum accumulator.
- Runtime tail masks for non-divisible channel tiles.
- 8-lane bias, ReLU, quantization, and saturation blocks.
- First 1x1 tiled engine milestone for one spatial sample with runtime `Cin/Cout`.
- Tensor address generation for stride/padding and first 3x3 tiled engine milestone for one output spatial sample.
- Activation and weight scratchpads with scalar load/debug ports and vector read ports for `PC` and `PK x PC` lanes.
- Ping-pong activation and weight scratchpads with lifecycle control for concurrent loading and compute-bank reads.
- Stream-to-scratchpad activation and weight load controllers with valid/ready handshakes, sequential tensor addressing, and config error checks.
- Output tensor store controller that streams computed tensors out in pixel/channel order with backpressure and `last` signaling.
- Full-image single-layer scheduler that reuses the 1x1/3x3 engines across output `x/y` positions.
- Three-layer RGB denoising descriptor ROM for the planned `3 -> 16 -> 16 -> 3` image-to-image network.
- Multi-layer job controller that sequences the three denoising layers through one reusable scheduler, alternates intermediate feature-map banks, waits for per-layer parameter readiness, and optionally performs final residual subtraction.
- Stream-loaded multi-layer job wrapper that starts compute after layer 0 is loaded, prefetches layer 1/2 parameters during compute, and streams final image output with backpressure.
- AXI-Stream v2 top-level wrapper with a single packetized tensor input, signed 32-bit output words, packet order/length validation, and protocol error reporting.
- Dependency-free bit-accurate Python integer model for image-to-image CNN arithmetic.
- Golden tensor flow for single-layer scheduler fixtures, the full 3-layer denoising controller, and the stream-loaded full-network wrapper.
- Directed v2 tests for 1x1, 3x3, address generation, tails, post-processing, and randomized MAC datapath coverage.
- Integrated AXI packet tests covering a complete seven-packet job, output backpressure, malformed lengths, packet ordering, invalid dimensions, and repeated starts.
- Dedicated v2 unit target.

Run:

```bash
make v2-model-test
make v2-golden-test
make v2-unit
```

See [docs/v2_image_to_image_architecture.md](docs/v2_image_to_image_architecture.md) and [docs/v2_stream_interface.md](docs/v2_stream_interface.md).

## Convolution Modes

### 1x1 Mode

```text
kernel_mode  = 0
active tap   = 0
output words = width * height * 4
```

For each RGB input pixel, the accelerator emits four output-channel values.

### 3x3 Mode

```text
kernel_mode  = 1
output words = (width - 2) * (height - 2) * 4
```

Tap order:

```text
tap 0   tap 1   tap 2
tap 3   tap 4   tap 5
tap 6   tap 7   tap 8
```

The generated identity-style test uses tap 4 as the center tap.

## Test Weights

The generated board test uses easy-to-inspect weights:

```text
output channel 0 = input channel R
output channel 1 = input channel G
output channel 2 = input channel B
output channel 3 = R + G + B
```

This makes simulation and bare-metal output comparison deterministic.

## Hardware Address Map

| Base | Peripheral |
|---:|---|
| `0x43C00000` | CNN AXI-Lite registers |
| `0x40400000` | AXI DMA registers |

## CNN Register Map

| Offset | Register | Notes |
|---:|---|---|
| `0x000` | `CONTROL` | bit 0 start, bit 1 clear |
| `0x004` | `STATUS` | busy/done/result status |
| `0x008` | `WIDTH` | input image width |
| `0x00C` | `HEIGHT` | input image height |
| `0x010` | `MODE_FLAGS` | kernel/ReLU/bias/quantization controls |
| `0x020` | `PIXEL_IN` | legacy AXI-Lite pixel path |
| `0x024` | `PIXEL_INDEX` | legacy/debug pixel index |
| `0x030` | `RESULT_DATA` | legacy AXI-Lite result path |
| `0x034` | `RESULT_STAT` | result status |
| `0x100` | `WEIGHT_BASE` | 108 signed 8-bit weights in 32-bit slots |
| `0x400` | `BIAS_BASE` | four signed 32-bit biases |

The current board path uses AXI DMA for image input and result output. AXI-Lite is still used for configuration.

## Mode Flags

| Bits | Name | Meaning |
|---:|---|---|
| `0` | `kernel_mode` | `0` = 1x1, `1` = 3x3 |
| `1` | `relu_enable` | enable ReLU |
| `2` | `bias_enable` | enable bias add |
| `3` | `quant_enable` | enable arithmetic right shift |
| `12:8` | `quant_shift` | quantization shift amount |

## Important RTL Files

| File | Purpose |
|---|---|
| [rtl/zynq/cnn_dma_system_top.sv](rtl/zynq/cnn_dma_system_top.sv) | Current DMA-capable top level |
| [rtl/zynq/cnn_axi_lite_slave.sv](rtl/zynq/cnn_axi_lite_slave.sv) | AXI-Lite register interface |
| [rtl/stream/axis_rgb_to_channels.sv](rtl/stream/axis_rgb_to_channels.sv) | Converts packed RGB stream into R/G/B channel samples |
| [rtl/fpga/streaming_cnn_core.sv](rtl/fpga/streaming_cnn_core.sv) | Main streaming 1x1/3x3 CNN core |
| [rtl/fpga/streaming_window_buffer.sv](rtl/fpga/streaming_window_buffer.sv) | Generates valid 3x3 windows |
| [rtl/compute/conv_engine.sv](rtl/compute/conv_engine.sv) | Pipelined MAC, bias, ReLU, quantization, saturation |
| [rtl/stream/axis_output_widen.sv](rtl/stream/axis_output_widen.sv) | Sign-extends int8 outputs to 32-bit DMA words |
| [rtl/cnn_accel_top.sv](rtl/cnn_accel_top.sv) | Earlier non-DMA prototype top used by legacy regression tests |
| [rtl/zynq/cnn_axi_system_top.sv](rtl/zynq/cnn_axi_system_top.sv) | Legacy AXI-Lite pixel/result system top |

## Verification

Run the full DMA top-level simulation:

```bash
make dma-sim
```

Expected result:

```text
[TEST] DMA top 3x3 mode
[TEST] DMA top 1x1 mode
[PASS] tb_cnn_dma_system_top tests=80
```

Other useful checks:

```bash
make regression
make axi-lite
make axi-system
make lint
```

Verification docs:

- [docs/verification_matrix.md](docs/verification_matrix.md)
- [docs/verification_plan.md](docs/verification_plan.md)
- [docs/logs/dma_top_sim_pass.log](docs/logs/dma_top_sim_pass.log)

## Generate Test Images

Generate a 3x3 test:

```bash
python3 scripts/image/generate_test_headers.py --width 8 --height 8 --kernel 3x3
```

Generate a 1x1 test:

```bash
python3 scripts/image/generate_test_headers.py --width 8 --height 8 --kernel 1x1
```

Generated files:

```text
software/zynq_baremetal/generated/test_image.h
software/zynq_baremetal/generated/expected_output.h
```

## Full Pre-Board Build Flow

```bash
make full-arty-z7-dma-flow
```

This flow:

1. Generates image headers.
2. Runs the DMA top simulation.
3. Creates the Vivado block design.
4. Builds the FPGA bitstream.
5. Exports the XSA.
6. Builds the Vitis bare-metal ELF.

For a board-arrival-ready proof package, run:

```bash
make preboard-proof
```

That adds warning-budget checking, `BOOT.BIN` generation, and a generated flow summary. Vitis cache/config data defaults to `build/vitis_data` so the flow does not depend on free space in the home-directory Vitis cache.

Generated artifacts are ignored by Git, but after a successful local build they should exist:

```text
build/arty_z7_20_cnn/arty_z7_20_cnn.runs/impl_1/system_wrapper.bit
build/arty_z7_20_cnn/arty_z7_20_cnn.xsa
build/vitis_ws/cnn_baremetal/build/cnn_baremetal.elf
build/BOOT.BIN
build/flow_report.md
```

Health-report commands:

```bash
make check-warnings
make flow-report
make boot-image
```

## Board Bring-Up

Board bring-up instructions are in [docs/BOARD_BRINGUP.md](docs/BOARD_BRINGUP.md).

When the Arty Z7-20 is available:

1. Connect the board over USB.
2. Set boot mode to JTAG.
3. Open UART at 115200 baud.
4. Run:

```bash
make program-arty-z7-dma
```

Expected UART output includes:

```text
Zynq CNN Accelerator DMA Test
CNN base address: 0x43c00000
DMA base address: 0x40400000
Kernel mode = 3x3
...
[PASS] CNN DMA accelerator test passed
```

## Documentation Map

| Document | Purpose |
|---|---|
| [docs/case_study.md](docs/case_study.md) | Interview-ready project narrative |
| [docs/block_diagram.md](docs/block_diagram.md) | DMA system and CNN pipeline diagrams |
| [docs/assets/arty_z7_dma_architecture.svg](docs/assets/arty_z7_dma_architecture.svg) | Generated architecture visual for portfolio/readme use |
| [docs/verification_matrix.md](docs/verification_matrix.md) | What has been tested and what remains |
| [docs/performance_analysis.md](docs/performance_analysis.md) | Throughput, latency, resource, and scaling analysis |
| [docs/pre_board_checklist.md](docs/pre_board_checklist.md) | Work to complete before hardware arrives |
| [docs/BOARD_BRINGUP.md](docs/BOARD_BRINGUP.md) | Board programming and debug checklist |
| [docs/known_warnings.md](docs/known_warnings.md) | Vivado warning budget and accepted generated-IP warnings |
| [docs/board_arrival_runbook.md](docs/board_arrival_runbook.md) | Exact evidence to capture when the board arrives |
| [docs/logs/pre_board_flow_report.md](docs/logs/pre_board_flow_report.md) | Snapshot of the latest pre-board artifact/timing/utilization report |
| [docs/logs/pre_board_warning_budget.log](docs/logs/pre_board_warning_budget.log) | Snapshot of the latest Vivado warning-budget pass |

## Current Limitations

- Physical Arty Z7-20 validation is pending hardware arrival.
- The bring-up CNN is intentionally small: 3 input channels and 4 output channels.
- Weights and biases are loaded through AXI-Lite registers, not through a DMA weight loader.
- Software currently polls DMA completion instead of using interrupts.
- The project is a portfolio/learning accelerator, not a production neural-network accelerator.

## Future Improvements

- Capture real board UART PASS log, setup photo, and demo clip.
- Archive measured board latency/throughput and optional ILA captures.
- Expose performance counters to software.
- Add interrupt-driven DMA completion.
- Add stride, padding, pooling, or a second layer.
- Add a DMA-based weight-loading path.

## Repository Status

The repository is ready for physical board validation. The next major milestone is running the generated DMA bare-metal test on the Arty Z7-20 and capturing proof of:

```text
[PASS] CNN DMA accelerator test passed
```
