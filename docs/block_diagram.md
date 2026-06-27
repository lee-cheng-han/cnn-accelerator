# Block Diagram

## Zynq System Block Diagram

```text
+-------------------------------------------------------------+
|                         Zynq-7000 SoC                        |
|                                                             |
|  +-----------------------------+                            |
|  | Processing System            |                            |
|  | ARM Cortex-A9                |                            |
|  | Bare-metal software          |                            |
|  +--------------+--------------+                            |
|                 |                                           |
|                 | M_AXI_GP0                                 |
|                 v                                           |
|  +-----------------------------+                            |
|  | AXI Interconnect             |                            |
|  +--------------+--------------+                            |
|                 |                                           |
|                 | AXI-Lite                                  |
|                 v                                           |
|  +-------------------------------------------------------+  |
|  | CNN AXI-Lite Accelerator                              |  |
|  |                                                       |  |
|  | +-------------------+   +---------------------------+ |  |
|  | | Control Registers |   | Status Registers          | |  |
|  | +-------------------+   +---------------------------+ |  |
|  |                                                       |  |
|  | +-------------------+   +---------------------------+ |  |
|  | | Weight Registers  |   | Bias Registers            | |  |
|  | +-------------------+   +---------------------------+ |  |
|  |                                                       |  |
|  | +-------------------+   +---------------------------+ |  |
|  | | Pixel Input       |-->| CNN Streaming Datapath    | |  |
|  | +-------------------+   +-------------+-------------+ |  |
|  |                                     |                 |  |
|  |                                     v                 |  |
|  |                         +---------------------------+ |  |
|  |                         | Result Buffer             | |  |
|  |                         +---------------------------+ |  |
|  +-------------------------------------------------------+  |
+-------------------------------------------------------------+
```

## Accelerator Datapath

```text
AXI-Lite Pixel Write
        |
        v
Pixel Input Register
        |
        v
Streaming Control
        |
        v
Window / Buffer Logic
        |
        v
Compute Datapath
        |
        v
Bias Add
        |
        v
ReLU
        |
        v
Quantization / Saturation
        |
        v
Result Buffer
        |
        v
AXI-Lite Result Read
```

## Software-Control Flow

```text
main.c
  |
  +-- write width / height
  |
  +-- write mode flags
  |
  +-- write weights
  |
  +-- write biases
  |
  +-- write start bit
  |
  +-- stream pixels through pixel input register
  |
  +-- read status
  |
  +-- read result data
  |
  +-- print output over UART
```

## Generated Hardware Flow

```text
RTL source
   |
   v
Vivado TCL project generation
   |
   v
Zynq block design
   |
   v
Synthesis
   |
   v
Implementation
   |
   v
Bitstream
   |
   v
XSA export
   |
   v
Vitis bare-metal application
```
