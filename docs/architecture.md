# Architecture

## Overview

The accelerator is implemented in the Zynq-7000 programmable logic and controlled by the ARM Cortex-A9 processing system through an AXI-Lite memory-mapped interface.

The design targets the Digilent Arty Z7-20. The Zynq processing system acts as the software controller, while the programmable logic contains the CNN accelerator, AXI-Lite register interface, configuration registers, streaming pixel input path, compute datapath, post-processing logic, and result buffer.

## Target Platform

| Item | Value |
|---|---|
| Board | Digilent Arty Z7-20 |
| SoC | Xilinx Zynq-7000 |
| FPGA Part | `xc7z020clg400-1` |
| Processor | Dual-core ARM Cortex-A9 |
| Interface | AXI-Lite |
| Toolchain | Vivado / Vitis 2025.2 |
| Accelerator Base Address | `0x43C00000` |

## System-Level Architecture

```text
ARM Cortex-A9 Processing System
        |
        | M_AXI_GP0
        v
AXI Interconnect
        |
        v
CNN AXI-Lite Accelerator
        |
        +-- Control / Status Registers
        +-- Image Dimension Registers
        +-- Mode Configuration Register
        +-- Weight Registers
        +-- Bias Registers
        +-- Pixel Input Register
        +-- Result Data Register
        +-- Result Status Register
```

The ARM processor configures the accelerator using AXI-Lite writes. It writes image size, mode flags, weights, biases, and input pixels. Output data is stored in the result buffer and read back through AXI-Lite.

## Datapath Overview

```text
Pixel Input Register
        |
        v
Streaming Input Control
        |
        v
Window / Buffer Logic
        |
        v
CNN Compute Datapath
        |
        v
Bias / ReLU / Quantization Logic
        |
        v
Result Buffer
        |
        v
AXI-Lite Readback
```

## Main Hardware Blocks

| Block | Purpose |
|---|---|
| AXI-Lite Slave | Provides software-visible control/status registers |
| Configuration Registers | Store image size, mode flags, weights, and biases |
| Streaming Pixel Input | Accepts input pixels from ARM software |
| Window / Buffer Logic | Buffers streamed image data for convolution-style processing |
| Compute Datapath | Performs CNN arithmetic operations |
| Post-Processing | Applies bias, ReLU, and quantization options |
| Result Buffer | Stores computed outputs for software readback |
| Zynq Wrapper | Connects the accelerator into the Vivado block design |

## AXI Register Map

| Offset | Register | Description |
|---:|---|---|
| `0x000` | Control | Start / clear control register |
| `0x004` | Status | Accelerator status |
| `0x008` | Width | Input image width |
| `0x00C` | Height | Input image height |
| `0x010` | Mode Flags | Kernel, ReLU, bias, and quantization configuration |
| `0x020` | Pixel Input | Streaming pixel input |
| `0x024` | Pixel Index | Pixel index / debug register |
| `0x030` | Result Data | Output result data |
| `0x034` | Result Status | Result buffer status |
| `0x100` | Weight Base | Weight register base |
| `0x400` | Bias Base | Bias register base |

## Mode Flags

| Bit | Name | Description |
|---:|---|---|
| `0` | Kernel Mode | Selects kernel/configuration mode |
| `1` | ReLU Enable | Enables ReLU post-processing |
| `2` | Bias Enable | Enables bias addition |
| `3` | Quant Enable | Enables output quantization |
| `12:8` | Quant Shift | Quantization right-shift amount |

## Software Interaction

The bare-metal ARM program accesses the accelerator through memory-mapped I/O:

```c
#define CNN_BASE 0x43C00000U
```

Software sequence:

1. Clear the accelerator
2. Configure image width and height
3. Configure mode flags
4. Load test weights
5. Load biases
6. Start the accelerator
7. Stream input pixels
8. Read status
9. Read output results
10. Print results through UART
