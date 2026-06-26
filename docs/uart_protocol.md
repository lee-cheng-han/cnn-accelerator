# UART Command Protocol

The FPGA receives byte commands over UART RX, runs the CNN accelerator, stores output bytes in a BRAM-backed result buffer, and sends results back through UART TX.

## UART Settings

Baud rate: 115200  
Data bits: 8  
Parity: None  
Stop bits: 1  
Flow control: None

## Commands

P
- Ping command.

C width_l width_h height_l height_h mode flags quant_shift
- Configures image size, kernel mode, feature flags, and quantization shift.
- width and height are little-endian 16-bit values.
- mode bit 0: 0 = 1x1, 1 = 3x3.
- flags bit 0 = ReLU enable.
- flags bit 1 = bias enable.
- flags bit 2 = quantization enable.

W <108 weight bytes>
- Loads all CNN weights.
- 4 output channels x 3 input channels x 9 taps = 108 weights.
- Each weight is signed INT8.
- Weight order:
  - output channel 0 to 3
  - input channel 0 to 2
  - tap 0 to 8
- In 1x1 mode, only tap 0 is used.

B <16 bias bytes>
- Loads 4 signed INT32 bias values.
- Each bias is little-endian.
- Order: bias0, bias1, bias2, bias3.

I len0 len1 len2 len3 <image bytes>
- Streams image bytes into the accelerator.
- Length is unsigned 32-bit little-endian.
- Image order:
  - y from 0 to height-1
  - x from 0 to width-1
  - channel 0, channel 1, channel 2
- Each channel value is signed INT8.
- The explicit length field makes image streaming safe because payload byte 0x52, ASCII R, is treated as image data and not as a read command.

R
- Reads result bytes from the FPGA over UART TX.

## Output Size

For 1x1 mode:

output bytes = width x height x 4 output channels

For 3x3 valid convolution mode:

output bytes = (width - 2) x (height - 2) x 4 output channels
