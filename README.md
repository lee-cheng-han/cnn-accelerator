# CNN Accelerator

SystemVerilog CNN accelerator for the **Digilent Arty Z7-20** using a **Zynq-7000 SoC**. The design integrates a custom CNN datapath into the Zynq programmable logic and exposes it to the ARM Cortex-A9 processing system through an AXI-Lite memory-mapped interface.

The repository includes RTL, verification, Vivado automation scripts, Zynq block design generation, bitstream generation, XSA export, and a Vitis bare-metal software application for controlling the accelerator from the ARM processor.

## Implementation Summary

| Item                       | Status              |
| -------------------------- | ------------------- |
| RTL simulation             | Passing             |
| AXI-Lite control interface | Complete            |
| Zynq PS to PL integration  | Complete            |
| Vivado block design        | Generated from TCL  |
| Bitstream generation       | Passing             |
| Timing closure             | Met                 |
| XSA hardware export        | Passing             |
| Vitis bare-metal app       | Builds successfully |
| Target board               | Digilent Arty Z7-20 |
| Accelerator base address   | `0x43C00000`        |

## FPGA Utilization

Latest implemented design on `xc7z020clg400-1`:

| Resource        |  Used | Available | Utilization |
| --------------- | ----: | --------: | ----------: |
| Slice LUTs      | 5,678 |    53,200 |      10.67% |
| Slice Registers | 7,749 |   106,400 |       7.28% |
| Block RAM Tile  |   4.5 |       140 |       3.21% |
| RAMB36/FIFO     |     4 |       140 |       2.86% |
| RAMB18          |     1 |       280 |       0.36% |
| DSPs            |     3 |       220 |       1.36% |

Timing result:

```text
All user specified timing constraints are met.
```

## Target Platform

| Item                         | Value                   |
| ---------------------------- | ----------------------- |
| Board                        | Digilent Arty Z7-20     |
| SoC                          | Xilinx Zynq-7000        |
| FPGA Part                    | `xc7z020clg400-1`       |
| Processor                    | Dual-core ARM Cortex-A9 |
| Programmable Logic Interface | AXI-Lite                |
| Toolchain                    | Vivado / Vitis 2025.2   |
| Software Environment         | Bare-metal standalone   |
| Accelerator Base Address     | `0x43C00000`            |

## System Architecture

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
        +-- Streaming Pixel Input Register
        +-- Result Data Register
        +-- Result Status Register
```

The ARM processor configures the accelerator through AXI-Lite writes, streams input pixels through a memory-mapped pixel input register, and reads computed outputs from the result buffer. The programmable logic contains the CNN datapath, buffering, control logic, and result storage.

## Hardware Features

* AXI-Lite memory-mapped control interface
* Zynq PS to PL integration through `M_AXI_GP0`
* Script-generated Vivado block design
* Streaming pixel input path
* Register-loaded weights and biases
* Result buffer with software readback
* ReLU, bias, and quantization configuration flags
* Bare-metal ARM software driver/test application
* Reproducible Vivado/Vitis build flow

## CNN Datapath Overview

The accelerator is structured around a streaming hardware datapath:

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

The software writes pixels into the accelerator one word at a time. The hardware receives the pixel stream, processes it through the configured CNN datapath, stores output values in the result buffer, and exposes the results through AXI-Lite reads.

## AXI Register Map

|  Offset | Register      | Description                                        |
| ------: | ------------- | -------------------------------------------------- |
| `0x000` | Control       | Start / clear control register                     |
| `0x004` | Status        | Accelerator status                                 |
| `0x008` | Width         | Input image width                                  |
| `0x00C` | Height        | Input image height                                 |
| `0x010` | Mode Flags    | Kernel, ReLU, bias, and quantization configuration |
| `0x020` | Pixel Input   | Streaming pixel input                              |
| `0x024` | Pixel Index   | Pixel index / debug register                       |
| `0x030` | Result Data   | Output result data                                 |
| `0x034` | Result Status | Result buffer status                               |
| `0x100` | Weight Base   | Weight register base                               |
| `0x400` | Bias Base     | Bias register base                                 |

## Mode Flags

|    Bit | Name         | Description                       |
| -----: | ------------ | --------------------------------- |
|    `0` | Kernel Mode  | Selects kernel/configuration mode |
|    `1` | ReLU Enable  | Enables ReLU post-processing      |
|    `2` | Bias Enable  | Enables bias addition             |
|    `3` | Quant Enable | Enables output quantization       |
| `12:8` | Quant Shift  | Quantization right-shift amount   |

## Program Structure

```text
cnn_accelerator/
├── rtl/
│   ├── compute/
│   │   └── CNN compute datapath modules
│   │
│   ├── fpga/
│   │   └── Streaming buffers, FPGA wrappers, and board-level datapath logic
│   │
│   └── zynq/
│       └── AXI-Lite slave, Zynq system top, and block design wrapper
│
├── tb/
│   └── SystemVerilog testbenches for RTL and AXI-level verification
│
├── scripts/
│   ├── zynq/
│   │   └── Vivado TCL scripts for project generation, synthesis, bitstream
│   │       generation, XSA export, and board programming
│   │
│   └── vitis/
│       └── Vitis Python scripts for bare-metal software generation
│
├── software/
│   └── zynq_baremetal/
│       └── Bare-metal ARM application for configuring and testing the accelerator
│
├── constraints/
│   └── FPGA constraint files
│
├── docs/
│   ├── architecture.md
│   ├── block_diagram.md
│   ├── performance_results.md
│   ├── synthesis_results.md
│   ├── verification_plan.md
│   └── zynq/
│       └── Zynq-specific integration documentation
│
├── Makefile
└── README.md
Documentation

Additional design documentation is available in the docs/ directory.

Document	Description
docs/architecture.md	Hardware architecture, datapath organization, and module-level design notes
docs/block_diagram.md	Text-based block diagrams for the CNN accelerator and Zynq integration
docs/performance_results.md	Implementation results, timing status, and resource utilization summary
docs/synthesis_results.md	Vivado synthesis results, warnings, and implementation notes
docs/verification_plan.md	Testbench strategy, directed/random testing approach, and verification coverage plan
docs/zynq/	Zynq PS/PL integration notes, AXI-Lite memory map details, and board bring-up flow
```

## Important Source Files

| File                                          | Purpose                                                  |
| --------------------------------------------- | -------------------------------------------------------- |
| `rtl/zynq/cnn_axi_lite_slave.sv`              | AXI-Lite register interface                              |
| `rtl/zynq/cnn_axi_system_top.sv`              | Top-level Zynq-facing accelerator wrapper                |
| `rtl/zynq/cnn_axi_system_bd_wrapper.v`        | Verilog wrapper used for Vivado block design integration |
| `rtl/fpga/streaming_window_buffer.sv`         | Streaming image/window buffering logic                   |
| `software/zynq_baremetal/main.c`              | Bare-metal ARM test application                          |
| `scripts/zynq/create_arty_z7_20_project.tcl`  | Creates the Vivado block design project                  |
| `scripts/zynq/build_arty_z7_20_bitstream.tcl` | Builds the implemented FPGA bitstream                    |
| `scripts/zynq/export_arty_z7_20_xsa.tcl`      | Exports the XSA hardware platform                        |
| `scripts/vitis/create_zynq_baremetal_app.py`  | Creates and builds the Vitis bare-metal application      |

## Software Flow

The bare-metal ARM application controls the accelerator through memory-mapped I/O.

Application source:

```text
software/zynq_baremetal/main.c
```

Base address:

```c
#define CNN_BASE 0x43C00000U
```

Program sequence:

1. Clear the accelerator
2. Configure image width and height
3. Configure accelerator mode flags
4. Load test weights
5. Load zero biases
6. Start the accelerator
7. Stream a small RGB test image
8. Read accelerator status
9. Read output results
10. Print results over UART

## Build Flow

### 1. Create the Vivado Project

```bash
make arty-z7-project
```

This generates the Vivado project and Zynq block design.

### 2. Build the Bitstream

```bash
make arty-z7-bitstream
```

Generated bitstream:

```text
build/arty_z7_20_cnn/arty_z7_20_cnn.runs/impl_1/system_wrapper.bit
```

### 3. Export the XSA

```bash
make arty-z7-xsa
```

Generated hardware platform:

```text
build/arty_z7_20_cnn/arty_z7_20_cnn.xsa
```

### 4. Build the Bare-Metal ARM Application

```bash
make vitis-app
```

Generated ELF:

```text
build/vitis_ws/cnn_baremetal/build/cnn_baremetal.elf
```

### 5. Full Hardware/Software Build

```bash
make full-arty-z7-flow
```

This runs the complete build sequence:

```text
Vivado project -> bitstream -> XSA -> Vitis bare-metal ELF
```

## Generated Outputs

Generated Vivado and Vitis outputs are not tracked in Git.

Ignored generated files include:

```text
build/
*.bit
*.xsa
*.elf
*.rpt
*.log
*.jou
.Xil/
xsim.dir/
```

A clean clone should regenerate all hardware and software outputs using the Makefile targets.

## Requirements

* Vivado 2025.2
* Vitis 2025.2
* Zynq-7000 / 7-Series device support
* Linux or WSL Ubuntu
* Digilent Arty Z7-20 board
* USB cable for programming and UART

For WSL users, Vitis may require:

```bash
sudo apt install -y x11-utils
```

## Notes

Generated Vivado and Vitis projects are intentionally excluded from version control. The repository tracks source RTL, software, constraints, scripts, and build targets. Hardware and software build products are regenerated from the scripted flow.
