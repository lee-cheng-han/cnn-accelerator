# FPGA-Ready UART CNN Accelerator

A hardware CNN accelerator written in SystemVerilog and prepared for FPGA board bring-up.  
The design supports a streaming UART interface for loading configuration, weights, bias values, and image data, then reading CNN results back over UART.

## Final Implementation Result

Full board-top integration was synthesized, placed, routed, and timing-checked in Vivado.

| Item | Result |
|---|---:|
| Target FPGA | TBD |
| Part | `TBD` |
| Tool | Vivado 2025.2 |
| Clock Target | 100 MHz |
| Timing Status | PASS |
| WNS | +0.489 ns |
| TNS | 0.000 ns |
| Failing Endpoints | 0 |

### Final Resource Utilization

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 4,992 | 20,800 | 24.00% |
| Slice Registers | 6,247 | 41,600 | 15.02% |
| Block RAM Tile | 4.5 | 50 | 9.00% |
| RAMB36 | 4 | 50 | 8.00% |
| RAMB18 | 1 | 100 | 1.00% |
| DSPs | 3 | 90 | 3.33% |
| Bonded IOB | 7 | 106 | 6.60% |

## Project Status

Current status:

- Full regression passes
- Board-level UART end-to-end simulation passes
- Full board-top synthesis passes
- Full board-top implementation passes
- 100 MHz timing closes successfully
- Result buffer infers BRAM
- Hardware bitstream generation is ready after adding board-specific XDC pin constraints

The project is hardware-ready at the RTL and implementation level. Final FPGA programming requires selecting a board and assigning physical pins for clock, reset, UART, and LEDs.

## Features

- Streaming CNN datapath
- 1x1 convolution mode
- 3x3 convolution mode
- 3 input channels
- 4 output channels
- INT8 input pixels
- INT8 weights
- INT32 accumulation
- Optional bias
- Optional ReLU
- Optional quantization shift
- INT8 output saturation
- UART command interface
- Config, weight, bias, and image loading
- BRAM-backed result buffer
- UART result readback
- Board-level top module with only 7 external I/O ports

## Top-Level Board Interface

Top module:

    cnn_accel_board_top

External ports:

| Port | Direction | Description |
|---|---|---|
| `clk` | input | FPGA clock |
| `rst_n` | input | Active-low reset |
| `uart_rx` | input | UART receive from host PC |
| `uart_tx` | output | UART transmit to host PC |
| `led_busy` | output | Indicates busy/not-ready activity |
| `led_done` | output | Toggles when result readback completes |
| `led_error` | output | Indicates UART/protocol/buffer error |

## Architecture Overview

The board-ready accelerator is organized as:

    uart_rx
      -> uart_cmd_decoder
      -> cnn_system_core
          -> cnn_config_loader
          -> streaming_cnn_core
          -> output_result_buffer
          -> uart_result_sender
      -> uart_tx

The design avoids storing a full image in a large activation buffer. Instead, it uses a streaming window-buffer architecture to generate convolution windows as pixels arrive.

This greatly reduces LUT and register usage compared to a full activation-memory approach.

## CNN Configuration

Default board configuration:

| Parameter | Value |
|---|---:|
| Input channels | 3 |
| Output channels | 4 |
| Kernel taps | 9 |
| Input data width | 8-bit signed |
| Weight width | 8-bit signed |
| Accumulator width | 32-bit signed |
| Output width | 8-bit signed |
| Result buffer depth | 16,384 bytes |

Supported convolution modes:

| Mode | Description |
|---|---|
| 1x1 | Uses tap 0 for each input channel |
| 3x3 | Uses all 9 taps per input channel |

## UART Protocol

Default UART settings:

| Setting | Value |
|---|---:|
| Baud rate | 115200 |
| Data bits | 8 |
| Parity | None |
| Stop bits | 1 |
| Flow control | None |

Command summary:

| Command | Payload | Description |
|---|---|---|
| `P` | none | Ping |
| `C` | 7 bytes | Configure image size, mode, flags, quantization |
| `W` | 108 bytes | Load CNN weights |
| `B` | 16 bytes | Load 4 signed INT32 bias values |
| `I` | 4-byte length + image bytes | Stream image data |
| `R` | none | Read output bytes |

Full protocol documentation is in:

    docs/uart_protocol.md

## Verification

The project includes directed and randomized SystemVerilog testbenches.

Verified modules include:

- MAC unit
- 3x3 MAC array
- channel accumulator
- window generator
- convolution engine
- streaming window buffer
- streaming CNN core
- UART RX
- UART TX
- UART command decoder
- CNN config loader
- output result buffer
- UART result sender
- CNN system core
- board-level UART top

Board-level tests include:

- compile test
- invalid command test
- full UART end-to-end test

Run full regression:

    make regression SEED=12345

## Implementation and Timing Closure

The original full-memory version did not fit efficiently because the activation buffer inferred a large LUT/FF-based memory.

The board-ready implementation fixed this by using:

- streaming pixel input
- line/window buffering
- BRAM-backed result storage
- UART-controlled loading and readback

A major timing issue came from calculating the total number of output windows directly from `image_width` and `image_height` and immediately using that result in control logic.

Timing was closed by pipelining:

1. total window multiply operands
2. total window count
3. last-window/control logic usage

Final result:

| Metric | Result |
|---|---:|
| Clock period | 10.000 ns |
| Frequency | 100 MHz |
| WNS | +0.489 ns |
| TNS | 0.000 ns |
| Status | PASS |

More details are in:

    docs/synthesis_results.md

## Host UART Script

A Python host script is provided for sending a demo image to the FPGA over UART.

Location:

    host/send_image_uart.py

Install dependency:

    pip install pyserial

Example Linux usage:

    python3 host/send_image_uart.py --port /dev/ttyUSB0 --baud 115200

Example Windows usage:

    python host/send_image_uart.py --port COM5 --baud 115200

The default demo sends a 4x4 image and verifies the returned CNN output.

Default 1x1 mapping:

    out0 = input_channel_0
    out1 = input_channel_1
    out2 = input_channel_2
    out3 = input_channel_0 + input_channel_1 + input_channel_2

## Repository Structure

    rtl/
      fpga/
        cnn_accel_board_top.sv
        cnn_system_core.sv
        streaming_cnn_core.sv
        streaming_window_buffer.sv
        uart_rx.sv
        uart_tx.sv
        uart_cmd_decoder.sv
        cnn_config_loader.sv
        output_result_buffer.sv
        uart_result_sender.sv

    tb/
      SystemVerilog testbenches

    scripts/
      simulation, regression, synthesis, and implementation scripts

    docs/
      uart_protocol.md
      synthesis_results.md

    host/
      send_image_uart.py

## Build and Test Commands

Run a single testbench:

    make xsim TB=tb_cnn_accel_board_top_e2e SEED=12345

Run full regression:

    make regression SEED=12345

Run full board-top synthesis:

    vivado -mode batch -source scripts/synth_real_board_top.tcl | tee synth_real_board_top.log

Check synthesis timing:

    grep -A 20 "Design Timing Summary" synth_out/real_board_top/timing_summary.rpt

Run full implementation:

    vivado -mode batch -source scripts/build_real_board_top_bitstream.tcl | tee build_real_board_top_bitstream.log

## Hardware Bring-Up

Final bitstream generation requires board-specific XDC constraints for:

- `clk`
- `rst_n`
- `uart_rx`
- `uart_tx`
- `led_busy`
- `led_done`
- `led_error`

Until a specific FPGA board is selected, the project should be described as:

    Synthesized, implemented, and timing-closed for Xilinx Artix-7 35T at 100 MHz.
    Hardware bring-up requires board-specific XDC pin constraints.

## Current Limitations

- Final hardware bitstream is blocked until a target board and XDC pin constraints are selected.
- UART bandwidth limits practical image size for interactive demos.
- The current board demo uses 3 input channels and 4 output channels.
- The project is intended as an FPGA/RTL accelerator demo, not a production-scale CNN inference engine.


