# Architecture

## Overview

The accelerator is implemented in the Zynq-7000 programmable logic and controlled by the ARM Cortex-A9 processing system.

The current board-facing design uses:

- AXI-Lite for control and configuration.
- AXI DMA for bulk image input and result output.
- AXI-Stream between the DMA engine and the CNN datapath.

The target board is the Digilent Arty Z7-20.

## Target Platform

| Item | Value |
|---|---|
| Board | Digilent Arty Z7-20 |
| SoC | Xilinx Zynq-7000 |
| FPGA part | `xc7z020clg400-1` |
| Processor | Dual-core ARM Cortex-A9 |
| PL clock | 100 MHz |
| Toolchain | Vivado / Vitis 2025.2 |
| CNN AXI-Lite base | `0x43C00000` |
| AXI DMA base | `0x40400000` |

## System-Level Architecture

```text
ARM Cortex-A9
    |
    | AXI-Lite through M_AXI_GP0
    v
AXI-Lite interconnect
    |
    +--> CNN configuration/status registers
    |
    +--> AXI DMA control registers


DDR input buffer
    |
    | AXI DMA MM2S
    v
CNN AXI-Stream input
    |
    v
CNN streaming datapath
    |
    v
CNN AXI-Stream output
    |
    | AXI DMA S2MM
    v
DDR output buffer
```

## Datapath

```text
AXI DMA MM2S
    |
    | 32-bit packed RGB pixels, 0x00BBGGRR
    v
axis_rgb_to_channels
    |
    | R, G, B channel-serial samples
    v
streaming_cnn_core
    |
    +--> 1x1 mode: collect one RGB pixel and use tap 0
    |
    +--> 3x3 mode: generate valid windows with streaming_window_buffer
    |
    v
conv_engine
    |
    | MAC, optional bias, optional ReLU, optional quantization, saturation
    v
axis_output_widen
    |
    | signed int8 result sign-extended to 32-bit AXI-Stream word
    v
AXI DMA S2MM
```

## Main Hardware Blocks

| Block | Purpose |
|---|---|
| `cnn_dma_system_top` | Current DMA-capable top-level accelerator |
| `cnn_axi_lite_slave` | Software-visible control/status/config register file |
| `cnn_config_loader` | Latches width, height, mode flags, weights, and biases |
| `axis_rgb_to_channels` | Converts packed RGB DMA input into channel samples |
| `streaming_window_buffer` | Generates valid 3x3 windows for channel-serial input |
| `streaming_cnn_core` | Sequences windows/pixels through the convolution engine |
| `conv_engine` | Pipelined convolution and post-processing datapath |
| `axis_output_widen` | Converts signed int8 outputs into 32-bit DMA words |
| AXI DMA | Moves image input and CNN output between DDR and PL streams |

## Register Map

| Offset | Register | Description |
|---:|---|---|
| `0x000` | Control | Start / clear control register |
| `0x004` | Status | Accelerator status |
| `0x008` | Width | Input image width |
| `0x00C` | Height | Input image height |
| `0x010` | Mode Flags | Kernel, ReLU, bias, and quantization configuration |
| `0x020` | Pixel Input | Legacy AXI-Lite input path |
| `0x024` | Pixel Index | Legacy/debug register |
| `0x030` | Result Data | Legacy AXI-Lite output path |
| `0x034` | Result Status | Result status |
| `0x100` | Weight Base | Weight register base |
| `0x400` | Bias Base | Bias register base |

The active board flow uses DMA for pixel input and result output. The AXI-Lite pixel/result registers remain for compatibility with earlier prototype paths.

## Mode Flags

| Bit | Name | Description |
|---:|---|---|
| `0` | Kernel Mode | `0` = 1x1 convolution, `1` = 3x3 convolution |
| `1` | ReLU Enable | Enables ReLU post-processing |
| `2` | Bias Enable | Enables bias addition |
| `3` | Quant Enable | Enables output quantization shift |
| `12:8` | Quant Shift | Arithmetic right-shift amount |

## Software Interaction

The bare-metal program accesses the accelerator and DMA through memory-mapped I/O:

```c
#define CNN_BASE 0x43C00000U
#define DMA_BASE 0x40400000U
```

Software sequence:

1. Clear the accelerator.
2. Configure image width and height.
3. Configure mode flags.
4. Load weights and biases.
5. Start the accelerator.
6. Start AXI DMA S2MM output transfer.
7. Start AXI DMA MM2S input transfer.
8. Wait for DMA completion.
9. Read status registers.
10. Compare DDR output buffer against generated golden output.

## Legacy Prototype Path

The repository also includes earlier non-DMA RTL and tests centered around `cnn_accel_top` and `cnn_axi_system_top`. Those modules are useful for regression history and simpler AXI-Lite experiments, but the current board validation target is the DMA system.
