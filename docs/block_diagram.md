# Block Diagram

## Current Zynq DMA System

```text
+-----------------------------------------------------------------------+
| Zynq-7000 SoC |
| |
| +-------------------------+ |
| | Processing System | |
| | ARM Cortex-A9 | |
| | bare-metal app | |
| +-----------+-------------+ |
| | |
| | M_AXI_GP0, AXI-Lite |
| v |
| +-------------------------+ |
| | AXI-Lite Interconnect | |
| +------+------------------+ |
| | |
| +-----------------------> CNN registers |
| | base 0x43C00000 |
| | |
| +-----------------------> AXI DMA control registers |
| base 0x40400000 |
| |
| +-------------------------+ |
| | DDR memory | |
| | packet/output buffers | |
| +----+---------------+----+ |
| ^ | |
| | v |
| +----+---------------+----+ |
| | AXI DMA | |
| | MM2S: DDR -> stream | |
| | S2MM: stream -> DDR | |
| +----+---------------+----+ |
| | ^ |
| | AXI-Stream | AXI-Stream |
| v | |
| +--------------------+--------------------+ |
| | cnn_image2image_system_top | |
| | packet router + stream-loaded CNN | |
| +-----------------------------------------+ |
+-----------------------------------------------------------------------+
```

## Active Data Path

```text
DDR tensor packet buffer
 |
 | AXI DMA MM2S
 v
32-bit AXI-Stream packets
 |
 v
tensor_packet_router
 |
 +--> activation stream
 +--> bias stream
 +--> weight stream
 v
stream_loaded_multi_layer_job_controller
 |
 +--> banked activation scratchpads
 +--> banked weight scratchpads
 +--> single_layer_scheduler
 +--> tiled 3x3 engines
 v
signed int8 RGB output
 |
 | sign-extended to 32-bit AXI-Stream words
 v
AXI DMA S2MM
 |
 v
DDR output buffer
```

## Software Control Flow

```text
software/zynq_baremetal/main.c
 |
 +-- reset AXI DMA
 +-- clear accelerator
 +-- write image width/height
 +-- write residual mode flag
 +-- start S2MM and MM2S DMA channels
 +-- pulse start
 +-- send seven tensor packets
 +-- wait for DMA and completion
 +-- print status/performance counters
 +-- compare DDR output against Python golden tensors
```

Expected board result:

```text
[PASS] image-to-image DMA golden test passed
```
