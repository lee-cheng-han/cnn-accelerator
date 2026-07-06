# Case Study: Zynq CNN Accelerator

## Problem

Build a small but complete FPGA CNN accelerator that can be controlled by software, receive image data from DDR, process it in programmable logic, and write results back to DDR for software validation.

The project goal is not to compete with a production neural-network accelerator. The goal is to demonstrate end-to-end ownership of an accelerator subsystem: RTL design, protocol integration, testbenches, synthesis, software, and board bring-up preparation.

## Constraints

| Constraint | Design choice |
|---|---|
| Target board | Digilent Arty Z7-20 |
| FPGA part | `xc7z020clg400-1` |
| Clock target | 100 MHz PL clock |
| Software control | ARM Cortex-A9 through AXI-Lite |
| Bulk data movement | AXI DMA |
| Bring-up data format | packed RGB, `0x00BBGGRR` |
| Arithmetic | signed int8 data and weights, signed int32 accumulation |
| Output format | signed int8 results sign-extended to 32-bit DMA words |

## Architecture

The current design has two independent software-visible paths:

- AXI-Lite configuration path for width, height, mode flags, weights, biases, start, clear, and status.
- AXI DMA data path for streaming packed RGB pixels into the accelerator and streaming 32-bit result words back to DDR.

The hardware path is:

```text
AXI DMA MM2S
  -> axis_rgb_to_channels
  -> streaming_cnn_core
  -> axis_output_widen
  -> AXI DMA S2MM
```

The CNN core supports:

- True 1x1 convolution using tap 0.
- Valid 3x3 convolution using a streaming window buffer.
- Four output channels.
- Bias add.
- ReLU.
- Quantization right shift.
- Saturation to signed int8.

## RTL Implementation

The DMA top level is `rtl/zynq/cnn_dma_system_top.sv`. It instantiates:

- `cnn_axi_lite_slave` for software-visible registers.
- `cnn_config_loader` for latching runtime configuration and loading weights/biases.
- `axis_rgb_to_channels` for converting one 32-bit packed RGB beat into three channel samples.
- `streaming_cnn_core` for CNN execution.
- `axis_output_widen` for turning signed int8 outputs into 32-bit AXI-Stream beats.

The compute datapath uses a pipelined `conv_engine`:

1. Multiply input samples by weights.
2. Sum kernel taps per input channel.
3. Accumulate input channels.
4. Apply optional bias, ReLU, quantization, and saturation.

## Verification

Verification is layered:

- Unit tests for MACs, channel accumulation, line/window buffers, RGB stream conversion, output widening, config loading, and output buffering.
- Directed and randomized tests for `conv_engine` and `streaming_cnn_core`.
- AXI-Lite register tests.
- Full DMA-style top-level test for both 3x3 and 1x1 modes.
- Python-generated C headers for repeatable bare-metal golden comparisons.

The DMA top simulation checks:

- AXI-Lite configuration writes.
- Packed RGB AXI-Stream input.
- 3x3 valid convolution.
- 1x1 convolution.
- Output ordering.
- Sign-extended 32-bit output words.
- Final TLAST behavior.

## Implementation Results

Latest documented implementation:

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 5,678 | 53,200 | 10.67% |
| Slice registers | 7,749 | 106,400 | 7.28% |
| Block RAM tile | 4.5 | 140 | 3.21% |
| DSPs | 3 | 220 | 1.36% |

Timing result:

```text
All user specified timing constraints are met.
```

## Software

The bare-metal application:

1. Copies generated packed RGB pixels into a DDR input buffer.
2. Clears and configures the accelerator.
3. Loads identity-style weights and zero biases.
4. Starts the accelerator.
5. Starts AXI DMA transfers.
6. Waits for MM2S and S2MM completion.
7. Invalidates the output cache range.
8. Compares the DDR output buffer against generated golden results.

Expected final board output:

```text
[PASS] CNN DMA accelerator test passed
```

## Current Status

Pre-board work is complete enough for hardware validation:

- RTL simulation passing.
- DMA block design generated.
- Bitstream built.
- XSA exported.
- Vitis bare-metal ELF built.
- Board validation pending physical Arty Z7-20 hardware.

## Lessons Learned

- A small accelerator becomes much more realistic once it uses a real data-movement path instead of only register writes.
- TLAST alignment matters because the compute pipeline has latency and can stall behind output backpressure.
- Separating configuration loading from stream processing keeps the DMA top easier to reason about.
- Simple generated images and identity-like weights are powerful for first board bring-up because failures are easy to inspect.
- The same RTL can look much stronger when the repo clearly separates current production-like paths from older prototype paths.

## Next Steps

- Run the bare-metal DMA test on physical hardware.
- Capture UART PASS log and setup photo.
- Archive measured hardware latency/throughput and any useful ILA captures.
- Expose performance counters to software.
- Add one architectural scaling feature, such as a second layer, stride/padding, or DMA-based weight loading.
