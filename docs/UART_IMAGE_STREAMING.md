# UART Image Streaming Mode

This mode lets a PC send different images to the Zynq board over UART without rebuilding the FPGA bitstream or recompiling the image into the ELF.

The Zynq ARM receives the image, stores it in DDR, starts AXI DMA, sends the image through the CNN accelerator, receives the output through AXI DMA, and sends the output back to the PC over UART.

## High-Level Flow

PC image file
   |
   v
PC Python script
   |
   | UART packet
   v
Zynq ARM Cortex-A9
   |
   | stores packed pixels in DDR input_buffer
   v
AXI DMA MM2S
   |
   v
CNN accelerator
   |
   v
AXI DMA S2MM
   |
   | stores result words in DDR output_buffer
   v
Zynq ARM Cortex-A9
   |
   | UART response packet
   v
PC reconstructs output image

## UART Speed Note

UART is useful for interactive testing, but it is not high bandwidth.

Recommended first image sizes:

- 16x16
- 32x32
- 64x64

The current RTL is configured for MAX_IMG_WIDTH = 64, so 64x64 is the initial maximum size unless the FPGA design is rebuilt with a larger max width.

## Input Packet: PC to Board

All integers are little-endian uint32.

Header:

Magic:        4 bytes  ASCII "CNNI"
Width:        uint32
Height:       uint32
Kernel mode:  uint32    0 = 1x1, 1 = 3x3
Pixel count:  uint32    width * height

Payload:

Pixels: pixel_count uint32 words

Each pixel is packed as:

0x00BBGGRR

Meaning:

bits 7:0    = R
bits 15:8   = G
bits 23:16  = B
bits 31:24  = unused

## Output Packet: Board to PC

All integers are little-endian uint32.

Header:

Magic:           4 bytes ASCII "CNNO"
Output width:    uint32
Output height:   uint32
Output channels: uint32
Output words:    uint32

Payload:

Output data: output_words int32 words

Current accelerator output format:

output channel 0 = R-like output
output channel 1 = G-like output
output channel 2 = B-like output
output channel 3 = R + G + B style output for identity test

For preview image reconstruction, the PC uses output channels 0, 1, and 2 as RGB.

## Output Size

For 1x1 mode:

output_width  = input_width
output_height = input_height

For 3x3 valid mode:

output_width  = input_width - 2
output_height = input_height - 2

Output words:

output_width * output_height * 4

## PC Command Example

Example:

python3 scripts/pc/send_image_uart.py input.png --port COM5 --width 32 --height 32 --kernel 3x3 --out output.png

On Linux/WSL with a USB serial device, the port may look like:

/dev/ttyUSB0
/dev/ttyACM0

## Board App

This mode should use a separate bare-metal app from the fixed generated-image validation app.

Stable validation app:

software/zynq_baremetal/main.c

UART image streaming app:

software/zynq_uart_image/main.c

The validation app should stay unchanged so the board can still run a simple PASS/FAIL hardware test first.

## Build UART Image App

Build the board-side UART image app:

```bash
make vitis-uart-image-app
