# Arty Z7-20 Board Bring-Up

## Required files

Bitstream:
build/arty_z7_20_cnn/arty_z7_20_cnn.runs/impl_1/system_wrapper.bit

ELF:
build/vitis_ws/cnn_baremetal/build/cnn_baremetal.elf

XSA:
build/arty_z7_20_cnn/arty_z7_20_cnn.xsa

## Hardware setup

1. Connect the Arty Z7-20 board over USB.
2. Set boot mode to JTAG.
3. Power on the board.
4. Open a UART terminal.

UART settings:
- Baud: 115200
- Data bits: 8
- Parity: none
- Stop bits: 1
- Flow control: none

## Program and run

Run:

make program-arty-z7-dma

This uses:

~/Xilinx/2025.2/Vitis/bin/xsct scripts/zynq/program_and_run_dma.tcl

## Expected UART output

The test should print:

Zynq CNN Accelerator DMA Test
CNN base address: 0x43c00000
DMA base address: 0x40400000
Kernel mode = 3x3
...
[PASS] CNN DMA accelerator test passed

## Important addresses

CNN AXI-Lite config base: 0x43C00000
AXI DMA base:             0x40400000

## DMA data path

DDR input buffer
   ↓
AXI DMA MM2S
   ↓ packed RGB AXI-Stream, 0x00BBGGRR
CNN accelerator
   ↓ 32-bit output AXI-Stream
AXI DMA S2MM
   ↓
DDR output buffer

## Debug lines to check if it fails

Paste these UART lines when debugging:

DMA MM2S status after reset
DMA S2MM status after reset
DMA MM2S final status
DMA S2MM final status
[FAIL] lines
