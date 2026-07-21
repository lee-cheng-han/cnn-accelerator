# Case Study: Zynq Image-to-Image CNN Accelerator

## Problem

Build a complete FPGA CNN accelerator subsystem that can be controlled by software, receive tensor data from DDR, process a multi-layer image-to-image network in programmable logic, and write results back to DDR for software validation.

The goal is to demonstrate end-to-end ownership of an accelerator subsystem: RTL microarchitecture, protocol integration, testbenches, synthesis, software, and board bring-up preparation.

## Constraints

| Constraint | Design choice |
|---|---|
| Target board | Digilent Zybo Z7-20 |
| FPGA part | `xc7z020clg400-1` |
| Clock target | 125 MHz PL clock |
| Software control | ARM Cortex-A9 through AXI-Lite |
| Bulk data movement | AXI DMA |
| Data format | seven-packet tensor stream |
| Network | RGB image-to-image, `3 -> 16 -> 16 -> 3` |
| Arithmetic | signed int8 data and weights, signed int32 accumulation |
| Output format | signed int8 RGB pixels sign-extended to 32-bit DMA words |

## Architecture

The current design has two software-visible paths:

- AXI-Lite configuration/status path for image dimensions, residual mode, start/clear, errors, and performance counters.
- AXI DMA data path for packetized activations, biases, weights, and output pixels.

The hardware path is:

```text
AXI DMA MM2S
 -> tensor_packet_router
 -> stream_loaded_multi_layer_job_controller
 -> scratchpad-backed tiled convolution engines
 -> AXI DMA S2MM
```

The core supports:

- Three fixed 3x3 convolution layers for RGB denoising-style reconstruction.
- Stream-loaded activation, bias, and weight tensors.
- Banked activation and weight scratchpads.
- Parameter prefetch overlap while compute is active.
- Optional final residual subtraction.
- Software-readable performance counters.

## RTL Implementation

The board-facing top level is `rtl/zynq/cnn_image2image_system_top.sv`. It instantiates:

- `cnn_axi_lite_slave` for software-visible registers and counters.
- `cnn_image2image_axi_stream_top` for packetized AXI-stream ingress/egress.
- `tensor_packet_router` for seven-packet validation and routing.
- `stream_loaded_multi_layer_job_controller` for tensor loading, compute, prefetch, and output streaming.
- `single_layer_scheduler` and tiled 1x1/3x3 engines for reusable image traversal and compute.

## Verification

Verification is layered:

- Unit tests for MAC arrays, accumulators, tail masks, post-processing, address generation, scratchpads, tensor loaders, and schedulers.
- Full-network RTL tests against generated Python golden tensors.
- Packetized AXI-stream tests for complete seven-packet jobs and malformed packet errors.
- AXI-Lite tests for register access, byte strobes, command pulses, interrupts, and performance snapshots.
- A Vitis bare-metal app that sends generated golden tensors through AXI DMA and checks returned pixels.

## Implementation Results

Latest board implementation:

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 7,501 | 53,200 | 14.10% |
| Slice registers | 7,673 | 106,400 | 7.21% |
| Block RAM tile | 29 | 140 | 20.71% |
| DSPs | 4 | 220 | 1.82% |

Timing result:

```text
All user specified timing constraints are met.
Clock = 125.000 MHz
WNS = 0.036 ns
WHS = 0.027 ns
```

## Software

The bare-metal application:

1. Generates and embeds a deterministic golden tensor job.
2. Clears and configures the accelerator.
3. Sends activation, bias, and weight packets through AXI DMA.
4. Receives output RGB pixels through AXI DMA.
5. Prints accelerator status and performance counters.
6. Compares both residual and non-residual output modes against Python golden tensors.

Expected final board output:

```text
[PASS] image-to-image DMA golden test passed
```

## Current Status

Pre-board work is complete enough for hardware validation:

- RTL simulation passing.
- Zynq block design generated.
- bitstream built and timing-clean at 125 MHz.
- XSA exported.
- Vitis bare-metal ELF built.
- BOOT.BIN packaging available.
- Board validation pending physical Zybo Z7-20 hardware.

## Lessons Learned

- A packetized tensor stream makes the accelerator feel like a real subsystem instead of a fixed demo datapath.
- Golden Python tensors are valuable because the same artifacts drive RTL and bare-metal checks.
- Streaming output directly, rather than mirroring whole frames for board use, substantially improves fit and timing.
- Keeping performance counters in the control plane makes board bring-up evidence much stronger.

## Next Steps

- Run the bare-metal DMA test on physical hardware.
- Capture UART PASS log and setup photo.
- Archive measured hardware latency/throughput and performance counters.
- Add an ILA/debug variant.
- Scale the board implementation toward `PC=4`, `PK=8`.
