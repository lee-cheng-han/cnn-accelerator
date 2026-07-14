# Zynq CNN Accelerator

[![CI](https://github.com/lee-cheng-han/cnn-accelerator/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/lee-cheng-han/cnn-accelerator/actions/workflows/ci.yml)
[![Vivado FPGA](https://github.com/lee-cheng-han/cnn-accelerator/actions/workflows/vivado-xsim.yml/badge.svg?branch=main)](https://github.com/lee-cheng-han/cnn-accelerator/actions/workflows/vivado-xsim.yml)
[![License](https://img.shields.io/github/license/lee-cheng-han/cnn-accelerator)](LICENSE)
![Target](https://img.shields.io/badge/target-Zybo%20Z7--20-1f6feb)
![Clock](https://img.shields.io/badge/clock-125%20MHz-2ea44f)

A SystemVerilog image-to-image CNN accelerator for the Digilent Zybo Z7-20 / Zynq-7000 platform. The programmable logic implements a packetized, multi-layer INT8 CNN datapath; the ARM Cortex-A9 configures it through AXI-Lite and moves tensor data through AXI DMA.

The project is currently in the final pre-board stage: RTL simulation, golden tensor verification, Vivado board implementation, XSA export, and Vitis bare-metal build are complete. Physical board validation is the next milestone when the Zybo Z7-20 arrives.

## Results Snapshot

| Area | Status |
|---|---|
| RTL language | SystemVerilog |
| Target board | Digilent Zybo Z7-20 |
| Vivado board part | `digilentinc.com:zybo-z7-20:part0:1.2` |
| FPGA part | `xc7z020clg400-1` |
| Toolchain | Vivado / Vitis 2025.2 |
| Control interface | AXI-Lite |
| Data interface | AXI DMA + AXI-Stream |
| Input format | Seven-packet tensor stream: activations, biases, weights |
| CNN network | 3-layer RGB denoising path, `3 -> 16 -> 16 -> 3` |
| Input / output channels | 3 RGB input channels, 3 RGB output channels |
| Data / weight / accumulator width | int8 / int8 / int32 |
| Timing | Met at 125 MHz |
| Board implementation | 7,169 LUTs / 7,603 registers |
| BRAM / DSP | 29 BRAM tiles / 4 DSPs |
| Worst slack | WNS +0.028 ns, WHS +0.004 ns |
| Golden RTL tests | Full 3-layer packetized AXI flow passing |
| Bitstream / XSA / ELF | Built |
| Board validation | Pending hardware |

Expected board-level result:

```text
[PASS] image-to-image DMA golden test passed
```

## Performance Snapshot

| Area | Evidence |
|---|---|
| Board clock | 125 MHz timing-clean Zynq block design |
| Board utilization | 13.48% LUT, 7.15% registers, 20.71% BRAM, 1.82% DSP |
| Implemented smoke config | `PC=2`, `PK=4`, `MAX_PIXELS=16` |
| Compute sweep baseline | `PC=4`, `PK=8` reaches 32 MACs/cycle |
| Peak compute estimate | 4.0 GMAC/s at 125 MHz for `PC=4`, `PK=8` |
| Software proof | bare-metal golden DMA app builds from the XSA |
| Hardware proof pending | UART PASS log after board arrival |

## Why This Project Matters

This repository demonstrates a complete FPGA accelerator subsystem:

- Microarchitecture: packetized tensor input, stream-loaded scratchpads, 3-layer CNN scheduling, post-processing, output streaming.
- Integration: Zynq PS, AXI-Lite control, AXI DMA, AXI-Stream datapath, Vivado block design automation.
- Verification: unit tests, randomized datapath tests, AXI packet tests, full-network golden tensor tests, generated Python reference tensors.
- Software: bare-metal C application that configures the accelerator, runs DMA tensor transfers, prints performance counters, and compares hardware output against golden data.
- Implementation: scripted Vivado project creation, bitstream generation, XSA export, and Vitis app build.

## Current Architecture

```text
ARM Cortex-A9
 |
 | AXI-Lite writes
 v
 config/status/performance registers
 |
 | image width/height, residual mode, start/clear
 v
 image-to-image CNN accelerator


DDR packet buffer
 |
 | AXI memory-mapped read
 v
AXI DMA MM2S
 |
 | AXI-Stream tensor packets
 v
tensor_packet_router
 |
 | activation, bias, weight streams
 v
stream_loaded_multi_layer_job_controller
 |
 | 3-layer RGB image-to-image CNN
 v
sign-extended 32-bit output stream
 v
AXI DMA S2MM
 |
 | AXI memory-mapped write
 v
DDR output buffer
```

The active board-facing top is [rtl/zynq/cnn_image2image_system_top.sv](rtl/zynq/cnn_image2image_system_top.sv), integrated into the Zynq block design through [rtl/zynq/cnn_image2image_system_bd_wrapper.v](rtl/zynq/cnn_image2image_system_bd_wrapper.v).

## Image-to-Image Path

The image-to-image path is the board-facing architecture for this repository.

Current status:

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
- AXI-Stream top-level wrapper with a single packetized tensor input, signed 32-bit output words, packet order/length validation, and protocol error reporting.
- AXI-Lite control/status bank with image configuration, command pulses, sticky interrupts, diagnostics, and software-readable performance counters.
- Integrated RTL system wrapper combining the AXI-Lite control plane and packetized AXI-Stream data plane.
- First Zynq block design with PS7, AXI DMA, AXI-Lite control, AXI-Stream datapath, bitstream generation, and XSA export at 125 MHz.
- bare-metal golden DMA app that sends the seven-packet tensor job, checks residual and non-residual outputs, and prints performance counters.
- performance counters for total latency, packet ingestion, scheduler activity, prefetch overlap, per-layer cycles, stream transfers, and backpressure.
- Reproducible out-of-context synthesis sweep for `PC/PK` scaling at 125 MHz; `PC=4`, `PK=8` provides 32 MACs/cycle with positive post-synthesis timing slack.
- Dependency-free bit-accurate Python integer model for image-to-image CNN arithmetic.
- Golden tensor flow for single-layer scheduler fixtures, the full 3-layer denoising controller, and the stream-loaded full-network wrapper.
- Directed tests for 1x1, 3x3, address generation, tails, post-processing, and randomized MAC datapath coverage.
- Integrated AXI packet tests covering a complete seven-packet job, output backpressure, malformed lengths, packet ordering, invalid dimensions, and repeated starts.
- Dedicated unit target.

Run:

```bash
make model-test
make golden-test
make unit
make synth-sweep
make full-zybo-z7-flow
make vitis-app
```

See [docs/image_to_image_architecture.md](docs/image_to_image_architecture.md), [docs/stream_interface.md](docs/stream_interface.md), [docs/register_map.md](docs/register_map.md), [docs/performance_counters.md](docs/performance_counters.md), [docs/synthesis_experiments.md](docs/synthesis_experiments.md), [docs/board_implementation.md](docs/board_implementation.md), and [docs/baremetal_app.md](docs/baremetal_app.md).

## Packetized Tensor Job

The board-facing job is a deterministic 3-layer RGB image-to-image workload. Software sends one AXI input stream containing seven packets:

```text
0: input activation tensor
1: layer 0 bias
2: layer 0 weights
3: layer 1 bias
4: layer 1 weights
5: layer 2 bias
6: layer 2 weights
```

Each packet starts with a 32-bit header:

```text
0xA5TT0000
```

where `TT` is the packet type. Payload words are signed INT8 for activations/weights and signed INT32 for biases. The output stream returns sign-extended signed INT8 RGB pixels as 32-bit DMA words.

The generated board software runs both:

```text
residual mode: output = input - predicted_noise
non-residual mode: output = raw final layer output
```

Both modes compare returned DMA output against generated Python golden tensors.

## Hardware Address Map

| Base | Peripheral |
|---:|---|
| `0x43C00000` | CNN AXI-Lite registers |
| `0x40400000` | AXI DMA registers |

## Register Map

The accelerator uses AXI-Lite for configuration, status, interrupts, diagnostics, and performance counters. Tensor payloads move through AXI DMA.

Key registers:

| Offset | Register | Notes |
|---:|---|---|
| `0x000` | `CONTROL` | bit 0 start pulse, bit 1 clear pulse |
| `0x004` | `STATUS` | busy, done, error, perf-counting |
| `0x010` | `IMAGE_WIDTH` | input/output image width |
| `0x014` | `IMAGE_HEIGHT` | input/output image height |
| `0x018` | `MODE_FLAGS` | bit 0 final residual subtraction enable |
| `0x01C` | `ERROR_CODE` | packet-router or compute error |
| `0x020` | `STREAM_STATE` | current packet type and ready-layer mask |
| `0x080`-`0x0A8` | `PERF_*` | job, packet, compute, prefetch, transfer, and stall counters |
| `0x0FC` | `VERSION` | currently `0x00020000` |

## Important RTL Files

| File | Purpose |
|---|---|
| [rtl/zynq/cnn_image2image_system_top.sv](rtl/zynq/cnn_image2image_system_top.sv) | AXI-Lite plus packetized AXI-Stream system top |
| [rtl/zynq/cnn_image2image_system_bd_wrapper.v](rtl/zynq/cnn_image2image_system_bd_wrapper.v) | Vivado block-design wrapper for the top |
| [rtl/zynq/cnn_axi_lite_slave.sv](rtl/zynq/cnn_axi_lite_slave.sv) | AXI-Lite register/status/performance interface |
| [rtl/zynq/cnn_image2image_axi_stream_top.sv](rtl/zynq/cnn_image2image_axi_stream_top.sv) | Packet router plus stream-loaded multi-layer controller |
| [rtl/stream/tensor_packet_router.sv](rtl/stream/tensor_packet_router.sv) | Validates seven-packet AXI tensor jobs |
| [rtl/scheduler/stream_loaded_multi_layer_job_controller.sv](rtl/scheduler/stream_loaded_multi_layer_job_controller.sv) | Loads tensors, prefetches parameters, runs the 3-layer scheduler |
| [rtl/scheduler/performance_counters.sv](rtl/scheduler/performance_counters.sv) | Software-readable latency, transfer, and stall counters |
| [rtl/compute](rtl/compute) | Tiled INT8 convolution engines and MAC datapath |
| [rtl/tensor](rtl/tensor) | Activation/weight scratchpads and tensor load/store controllers |

## Verification

Run the software/model/RTL regression:

```bash
make regression
```

Expected golden RTL output includes:

```text
[PASS] tb_axi_stream_full_network_golden_flow
```

Other useful checks:

```bash
make regression
make lint
```

Verification docs:

- [docs/verification_matrix.md](docs/verification_matrix.md)
- [docs/verification_plan.md](docs/verification_plan.md)
- [docs/baremetal_app.md](docs/baremetal_app.md)
- [docs/stream_interface.md](docs/stream_interface.md)

## Generate Golden Tensor Job

Generate Python golden tensors and the C DMA packet header:

```bash
make baremetal-headers
```

Generated files:

```text
build/golden/full_network_3layer/
software/zynq_baremetal/generated/golden_dma_job.h
```

## Full Pre-Board Build Flow

```bash
make full-preboard-proof
```

This flow:

1. Regenerates golden tensors and the C DMA packet header.
2. Runs model, golden, and unit regressions.
3. Creates the Vivado block design.
4. Builds the FPGA bitstream.
5. Exports the XSA.
6. Builds the Vitis bare-metal ELF and FSBL.
7. Packages `build/BOOT.BIN`.

For a board-arrival-ready proof package, run:

```bash
make preboard-proof
```

`preboard-proof` is now an alias for the proof flow. Vitis cache/config data defaults to `build/vitis_data` so the flow does not depend on free space in the home-directory Vitis cache.

Generated artifacts are ignored by Git, but after a successful local build they should exist:

```text
build/zybo_z7_20_cnn/zybo_z7_20_cnn.runs/impl_1/system_wrapper.bit
build/zybo_z7_20_cnn/zybo_z7_20_cnn.xsa
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

When the Zybo Z7-20 is available:

1. Connect the board over USB.
2. Set boot mode to JTAG.
3. Open UART at 115200 baud.
4. Run:

```bash
make program-zybo-z7
```

Expected UART output includes:

```text
Zynq Image-to-Image CNN DMA Test
CNN base address: 0x43c00000
AXI DMA base address: 0x40400000
...
[PASS] image-to-image DMA golden test passed
```

## Documentation Map

| Document | Purpose |
|---|---|
| [docs/case_study.md](docs/case_study.md) | Interview-ready project narrative |
| [docs/block_diagram.md](docs/block_diagram.md) | DMA system and CNN pipeline diagrams |
| [docs/verification_matrix.md](docs/verification_matrix.md) | What has been tested and what remains |
| [docs/performance_results.md](docs/performance_results.md) | Throughput, timing, resource, and scaling results |
| [docs/register_map.md](docs/register_map.md) | AXI-Lite software register and interrupt contract |
| [docs/synthesis_experiments.md](docs/synthesis_experiments.md) | Reproducible PC/PK synthesis tradeoff results |
| [docs/pre_board_checklist.md](docs/pre_board_checklist.md) | Work to complete before hardware arrives |
| [docs/BOARD_BRINGUP.md](docs/BOARD_BRINGUP.md) | Board programming and debug checklist |
| [docs/known_warnings.md](docs/known_warnings.md) | Vivado warning budget and accepted generated-IP warnings |
| [docs/board_arrival_runbook.md](docs/board_arrival_runbook.md) | Exact evidence to capture when the board arrives |
| [docs/logs/pre_board_flow_report.md](docs/logs/pre_board_flow_report.md) | Snapshot of the latest pre-board artifact/timing/utilization report |
| [docs/logs/pre_board_warning_budget.log](docs/logs/pre_board_warning_budget.log) | Snapshot of the latest Vivado warning-budget pass |

## Current Limitations

- Physical Zybo Z7-20 validation is pending hardware arrival.
- The board-facing smoke configuration is intentionally small: `PC=2`, `PK=4`, `MAX_PIXELS=16`.
- Weights and biases are packet-loaded through AXI DMA for the flow.
- Software currently polls DMA completion instead of using interrupts.
- The project is a portfolio/learning accelerator, not a production neural-network accelerator.

## Future Improvements

- Capture real board UART PASS log, setup photo, and demo clip.
- Archive measured board latency/throughput and optional ILA captures.
- Validate the UART PASS path on physical hardware.
- Add interrupt-driven DMA completion.
- Add an ILA debug variant.
- Scale the board implementation toward `PC=4`, `PK=8`.

## Repository Status

The repository is ready for physical board validation. The next major milestone is running the generated DMA bare-metal test on the Zybo Z7-20 and capturing proof of:

```text
[PASS] image-to-image DMA golden test passed
```
