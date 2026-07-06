# Block Diagram

## Current Zynq DMA System

```text
+-----------------------------------------------------------------------+
|                              Zynq-7000 SoC                             |
|                                                                       |
|  +-------------------------+                                          |
|  | Processing System       |                                          |
|  | ARM Cortex-A9           |                                          |
|  | Bare-metal C test app   |                                          |
|  +-----------+-------------+                                          |
|              |                                                        |
|              | M_AXI_GP0, AXI-Lite                                    |
|              v                                                        |
|  +-------------------------+                                          |
|  | AXI-Lite Interconnect   |                                          |
|  +------+------------------+                                          |
|         |                                                             |
|         +-----------------------> CNN config registers                 |
|         |                         base 0x43C00000                     |
|         |                                                             |
|         +-----------------------> AXI DMA control registers            |
|                                   base 0x40400000                     |
|                                                                       |
|  +-------------------------+                                          |
|  | DDR memory              |                                          |
|  | input/output buffers    |                                          |
|  +----+---------------+----+                                          |
|       ^               |                                               |
|       |               v                                               |
|  +----+---------------+----+                                          |
|  | AXI DMA                 |                                          |
|  | MM2S: DDR -> stream     |                                          |
|  | S2MM: stream -> DDR     |                                          |
|  +----+---------------+----+                                          |
|       |               ^                                               |
|       | AXI-Stream    | AXI-Stream                                    |
|       v               |                                               |
|  +--------------------+--------------------+                          |
|  | cnn_dma_system_top                       |                          |
|  | AXI-Lite config + streaming CNN datapath |                          |
|  +-----------------------------------------+                          |
+-----------------------------------------------------------------------+
```

## Active Data Path

```text
DDR input image
    |
    | AXI DMA MM2S
    v
32-bit AXI-Stream pixels
0x00BBGGRR
    |
    v
axis_rgb_to_channels
    |
    | R, then G, then B for each pixel
    v
streaming_cnn_core
    |
    +--> 1x1 path:
    |       collect R/G/B for one pixel
    |       use tap 0 only
    |
    +--> 3x3 path:
            streaming_window_buffer
            generate valid 3x3 windows
    |
    v
conv_engine
    |
    | multiply -> channel sum -> output-channel sum
    | optional bias -> optional ReLU -> optional quant shift
    | saturate to signed int8
    v
output FIFO inside streaming_cnn_core
    |
    v
axis_output_widen
    |
    | sign-extend int8 result to 32-bit word
    v
AXI DMA S2MM
    |
    v
DDR output buffer
```

## Control Flow

```text
software/zynq_baremetal/main.c
    |
    +-- clear accelerator
    +-- write width and height
    +-- write mode flags
    +-- write 108 weight registers
    +-- write 4 bias registers
    +-- start accelerator
    +-- configure AXI DMA S2MM output transfer
    +-- configure AXI DMA MM2S input transfer
    +-- wait for both DMA channels to complete
    +-- compare DDR output buffer against generated golden output
```

## CNN Pipeline

```text
input sample/window
    |
    v
Stage 1: multiply each active input/tap by selected weights
    |
    v
Stage 2: sum tap products per input channel
    |
    v
Stage 3: accumulate input-channel sums
    |
    v
Stage 4: bias/ReLU/quantize/saturate
    |
    v
signed int8 output
```

## Legacy Prototype Path

The repository also contains an earlier AXI-Lite pixel/result path:

```text
AXI-Lite pixel write -> cnn_accel_top / cnn_axi_system_top -> AXI-Lite result read
```

That path is useful for historical comparison and some legacy tests, but the current board-facing design is the DMA path through `cnn_dma_system_top`.
