# Zynq CNN Accelerator

A SystemVerilog CNN accelerator targeting the Digilent Arty Z7-20 / Zynq-7000 platform. The accelerator is controlled by the ARM Cortex-A9 through AXI-Lite and streams image data through AXI DMA.

The design supports both true 1x1 convolution and 3x3 convolution. It includes generated-image test vectors, XSim testbenches, Vivado block design automation, and a bare-metal C test application for board validation.

## Project Status

Current status before physical board validation:

- RTL simulation: passing
- AXI-Lite control path: implemented
- AXI-Stream data path: implemented
- AXI DMA block design: implemented
- Vivado bitstream: built
- XSA export: complete
- Vitis bare-metal ELF: built
- Board validation: pending Arty Z7-20 hardware

Expected final board result:

    [PASS] CNN DMA accelerator test passed

## Features

- Zynq-7000 PS + FPGA accelerator design
- AXI-Lite register interface for configuration
- AXI DMA input and output streaming
- Packed RGB input format: 0x00BBGGRR
- 3 input channels: R, G, B
- 4 output channels
- True 1x1 convolution mode
- 3x3 valid convolution mode
- Bias support
- ReLU support
- Quantization-shift support in the register map
- Generated C image headers for repeatable testing
- Golden-output comparison in bare-metal software
- XSim simulation testbenches
- Vivado block design script for Arty Z7-20
- Vitis bare-metal application build script

## System Architecture

High-level data path:

    ARM Cortex-A9
         |
         | AXI-Lite
         v
    CNN configuration registers
         |
         | width / height / mode / weights / bias
         v
    CNN accelerator core


    DDR input buffer
         |
         | AXI memory-mapped read
         v
    AXI DMA MM2S
         |
         | AXI-Stream packed RGB pixels
         | one beat = 0x00BBGGRR
         v
    axis_rgb_to_channels
         |
         | R, G, B channel stream
         v
    streaming_cnn_core
         |
         | signed 8-bit CNN outputs
         v
    axis_output_widen
         |
         | 32-bit AXI-Stream outputs
         v
    AXI DMA S2MM
         |
         | AXI memory-mapped write
         v
    DDR output buffer

## Hardware Address Map

The Vivado block design exports the following base addresses:

    CNN AXI-Lite base: 0x43C00000
    AXI DMA base:      0x40400000

## CNN Register Map

    Offset      Register
    0x000       CONTROL
    0x004       STATUS
    0x008       WIDTH
    0x00C       HEIGHT
    0x010       MODE_FLAGS
    0x020       PIXEL_IN        legacy AXI-Lite input path
    0x024       PIXEL_INDEX     legacy AXI-Lite input path
    0x030       RESULT_DATA     legacy AXI-Lite output path
    0x034       RESULT_STAT
    0x100       WEIGHT_BASE
    0x400       BIAS_BASE

The DMA design uses AXI DMA for pixel input and output, but the AXI-Lite registers are still used for configuration.

## Mode Flags

    Bit(s)      Meaning
    0           kernel_mode
                0 = 1x1 convolution
                1 = 3x3 convolution

    1           relu_enable
    2           bias_enable
    3           quant_enable
    12:8        quant_shift

## Convolution Modes

### 1x1 Mode

In 1x1 mode, the core performs convolution using only one tap.

    kernel_mode = 0
    active tap  = 0
    output words = width * height * 4

For each input pixel, the accelerator produces 4 output-channel values.

### 3x3 Mode

In 3x3 mode, the core performs valid 3x3 convolution.

    kernel_mode = 1
    center tap  = 4
    output words = (width - 2) * (height - 2) * 4

3x3 tap order:

    tap 0   tap 1   tap 2
    tap 3   tap 4   tap 5
    tap 6   tap 7   tap 8

For the identity-style generated test, tap 4 is used as the center tap.

## CNN Test Weights

The generated test uses simple identity-like weights:

    output channel 0 = input channel R
    output channel 1 = input channel G
    output channel 2 = input channel B
    output channel 3 = R + G + B

This makes the hardware output easy to compare against a software-generated golden output.

## Main RTL Files

    rtl/zynq/cnn_dma_system_top.sv
        Top-level DMA-capable CNN system.
        Combines AXI-Lite configuration, AXI-Stream input, CNN core, and AXI-Stream output.

    rtl/zynq/cnn_dma_system_bd_wrapper.v
        Vivado block design module wrapper for cnn_dma_system_top.

    rtl/zynq/cnn_axi_lite_slave.sv
        AXI-Lite register interface used by the ARM processor.

    rtl/stream/axis_rgb_to_channels.sv
        Converts 32-bit packed RGB AXI-Stream input into sequential R, G, B channel samples.

    rtl/stream/axis_output_widen.sv
        Converts signed 8-bit CNN outputs into 32-bit AXI-Stream words for AXI DMA S2MM.

    rtl/fpga/streaming_cnn_core.sv
        Main streaming CNN computation core.
        Supports both 1x1 and 3x3 modes.

    rtl/fpga/streaming_window_buffer.sv
        Generates 3x3 windows from the incoming channel stream.

    rtl/compute/conv_engine.sv
        Performs the multiply-accumulate convolution operation.

## Testbench Files

    tb/stream/tb_axis_rgb_to_channels.sv
        Unit test for the AXI-Stream RGB input adapter.

    tb/stream/tb_axis_output_widen.sv
        Unit test for the AXI-Stream output widening adapter.

    tb/stream/tb_cnn_dma_system_top.sv
        Full DMA-style top-level simulation.
        Tests AXI-Lite configuration, AXI-Stream input, CNN processing, and AXI-Stream output.

    tb/zynq/tb_cnn_axi_lite_slave.sv
        AXI-Lite register testbench.

    tb/zynq/tb_cnn_axi_system_top.sv
        Legacy AXI-Lite system-level testbench.

## Software Files

    software/zynq_baremetal/main.c
        Bare-metal C test application.
        Configures the CNN accelerator, starts AXI DMA transfers, and compares the output buffer against golden data.

    software/zynq_baremetal/generated/test_image.h
        Generated input image data.

    software/zynq_baremetal/generated/expected_output.h
        Generated golden output data.

## Script Files

    scripts/image/generate_test_headers.py
        Generates test_image.h and expected_output.h.

    scripts/zynq/create_arty_z7_20_project.tcl
        Creates the Vivado project and block design for Arty Z7-20.

    scripts/zynq/build_arty_z7_20_bitstream.tcl
        Builds the FPGA bitstream.

    scripts/zynq/export_arty_z7_20_xsa.tcl
        Exports the hardware XSA for Vitis.

    scripts/zynq/run_dma_top_tb.sh
        Runs the full DMA top-level XSim testbench.

    scripts/zynq/program_and_run_dma.tcl
        Programs the board and runs the bare-metal ELF through XSCT.

    scripts/vitis/create_zynq_baremetal_app.py
        Creates and builds the Vitis bare-metal application.

## Requirements

Tested with:

    Vivado 2025.2
    Vitis 2025.2
    XSim
    Ubuntu / WSL
    Target board: Digilent Arty Z7-20

Expected tool paths:

    ~/Xilinx/2025.2/Vivado/bin/vivado
    ~/Xilinx/2025.2/Vitis/bin/vitis
    ~/Xilinx/2025.2/Vitis/bin/xsct

## Generate Test Images

Generate a 3x3 test:

    python3 scripts/image/generate_test_headers.py --width 8 --height 8 --kernel 3x3

Generate a 1x1 test:

    python3 scripts/image/generate_test_headers.py --width 8 --height 8 --kernel 1x1

Generated files:

    software/zynq_baremetal/generated/test_image.h
    software/zynq_baremetal/generated/expected_output.h

## Run Simulation

Run the full DMA top-level simulation:

    make dma-sim

Expected result:

    [TEST] DMA top 3x3 mode
    [TEST] DMA top 1x1 mode
    [PASS] tb_cnn_dma_system_top tests=80

This verifies:

- AXI-Lite configuration writes
- AXI-Stream packed RGB input
- 1x1 mode
- 3x3 mode
- 32-bit AXI-Stream output
- Correct output ordering
- Correct TLAST behavior

## Full Pre-Board Build Flow

Run:

    make full-arty-z7-dma-flow

This performs:

1. Generate image headers
2. Run DMA top simulation
3. Create Vivado block design
4. Build FPGA bitstream
5. Export XSA
6. Build Vitis bare-metal ELF

## Build Artifacts

Generated artifacts are ignored by Git, but after a successful build they should exist locally:

    build/arty_z7_20_cnn/arty_z7_20_cnn.runs/impl_1/system_wrapper.bit
    build/arty_z7_20_cnn/arty_z7_20_cnn.xsa
    build/vitis_ws/cnn_baremetal/build/cnn_baremetal.elf

## XSA Hardware Check

To confirm the exported XSA contains the DMA system:

    mkdir -p /tmp/cnn_xsa_check
    unzip -o build/arty_z7_20_cnn/arty_z7_20_cnn.xsa -d /tmp/cnn_xsa_check >/dev/null

    grep -R "43C00000\|40400000\|axi_dma\|cnn_axi" -n /tmp/cnn_xsa_check | head -100

Expected evidence:

    axi_dma_0
    cnn_axi_0
    0x40400000
    0x43C00000
    M_AXIS_MM2S connected to CNN input
    CNN output connected to S_AXIS_S2MM

## Board Bring-Up

Board bring-up instructions are in:

    docs/BOARD_BRINGUP.md

When the Arty Z7-20 board is available:

1. Connect board over USB.
2. Set boot mode to JTAG.
3. Open UART at 115200 baud.
4. Run:

       make program-arty-z7-dma

Expected UART output:

    Zynq CNN Accelerator DMA Test
    CNN base address: 0x43c00000
    DMA base address: 0x40400000
    Kernel mode = 3x3
    ...
    [PASS] CNN DMA accelerator test passed

## Verification Completed Before Board

Completed pre-board checks:

- AXI-Lite register simulation
- AXI-Lite system simulation
- Generated image header flow
- 1x1 generated-image software build
- 3x3 generated-image software build
- AXI-Stream input adapter simulation
- AXI-Stream output adapter simulation
- Full DMA top simulation
- DMA Vivado block design creation
- DMA bitstream build
- DMA XSA export
- DMA bare-metal ELF build

## Current Limitations

- Board validation is pending until physical Arty Z7-20 hardware is available.
- Current generated tests use small images for bring-up.
- Current software uses polling instead of DMA interrupts.
- The design is intended as a portfolio/learning accelerator, not a production neural-network accelerator.

## Future Improvements

Possible next improvements:

- Add interrupt-driven DMA completion
- Add larger image tests
- Add more output channels
- Add multiple convolution layers
- Add pooling
- Add configurable stride/padding
- Add performance counters visible in software
- Add UART performance summary
- Add board PASS log and screenshot after hardware validation

## Repository Status

This repository is currently ready for physical board validation.

The next major milestone is running the generated DMA bare-metal test on the Arty Z7-20 and capturing UART proof of:

    [PASS] CNN DMA accelerator test passed
