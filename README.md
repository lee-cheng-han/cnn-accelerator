# Zynq CNN Accelerator

A SystemVerilog CNN accelerator targeting the Digilent Arty Z7-20 / Zynq-7000 platform.

The design supports both true 1x1 convolution and 3x3 convolution. It uses AXI-Lite for configuration and AXI DMA for image input/output streaming.

## Features

- Zynq PS + FPGA CNN accelerator
- AXI-Lite control/status register interface
- AXI DMA input/output data movement
- Packed RGB input stream: 0x00BBGGRR
- 3 input channels
- 4 output channels
- 1x1 mode and 3x3 mode
- Bias and ReLU support
- Bare-metal C test application
- Golden-output comparison
- Vivado/XSim simulation testbenches

## Architecture

ARM Cortex-A9
   |
   | AXI-Lite
   v
CNN config registers

DDR input buffer
   |
   v
AXI DMA MM2S
   |
   | packed RGB AXI-Stream
   v
axis_rgb_to_channels
   |
   v
streaming_cnn_core
   |
   v
axis_output_widen
   |
   | 32-bit AXI-Stream
   v
AXI DMA S2MM
   |
   v
DDR output buffer

## Addresses

CNN base address: 0x43C00000
DMA base address: 0x40400000

## CNN register map

0x000 CONTROL
0x004 STATUS
0x008 WIDTH
0x00C HEIGHT
0x010 MODE_FLAGS
0x100 WEIGHT_BASE
0x400 BIAS_BASE

## Mode flags

bit 0      kernel_mode: 0 = 1x1, 1 = 3x3
bit 1      relu_enable
bit 2      bias_enable
bit 3      quant_enable
bits 12:8  quant_shift

## Convolution modes

1x1 mode:
- kernel_mode = 0
- active weight tap = 0
- output words = width * height * 4

3x3 mode:
- kernel_mode = 1
- active center tap = 4
- output words = (width - 2) * (height - 2) * 4

3x3 tap order:

tap 0 tap 1 tap 2
tap 3 tap 4 tap 5
tap 6 tap 7 tap 8

## Run DMA top simulation

make dma-sim

Expected result:

[PASS] tb_cnn_dma_system_top tests=80

## Full pre-board build flow

make full-arty-z7-dma-flow

This runs:
1. Generate image headers
2. Run DMA top simulation
3. Create Vivado block design
4. Build bitstream
5. Export XSA
6. Build Vitis bare-metal ELF

## Generated image tests

Generate a 3x3 test:

python3 scripts/image/generate_test_headers.py --width 8 --height 8 --kernel 3x3

Generate a 1x1 test:

python3 scripts/image/generate_test_headers.py --width 8 --height 8 --kernel 1x1

Generated files:
- software/zynq_baremetal/generated/test_image.h
- software/zynq_baremetal/generated/expected_output.h

## Board bring-up

See docs/BOARD_BRINGUP.md

Program and run on board:

make program-arty-z7-dma

Expected UART result:

[PASS] CNN DMA accelerator test passed

## Key source files

- rtl/zynq/cnn_dma_system_top.sv
- rtl/zynq/cnn_dma_system_bd_wrapper.v
- rtl/stream/axis_rgb_to_channels.sv
- rtl/stream/axis_output_widen.sv
- rtl/fpga/streaming_cnn_core.sv
- software/zynq_baremetal/main.c
- scripts/zynq/create_arty_z7_20_project.tcl
- scripts/zynq/program_and_run_dma.tcl

## Current status

- Simulation: passing
- Vivado DMA block design: created
- Bitstream: built
- XSA: exported
- Vitis ELF: built
- Board validation: pending Arty Z7-20 hardware
