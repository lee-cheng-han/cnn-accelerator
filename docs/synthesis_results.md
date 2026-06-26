# Synthesis and Implementation Results

Target used for implementation testing:

- FPGA family: Xilinx Artix-7
- Part: xc7a35tcpg236-1
- Top module: cnn_accel_board_top
- Clock target: 100 MHz
- Tool: Vivado 2025.2

## Final Board-Top Utilization

Full UART + CNN board integration result:

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 4,992 | 20,800 | 24.00% |
| Slice Registers | 6,247 | 41,600 | 15.02% |
| Block RAM Tile | 4.5 | 50 | 9.00% |
| RAMB36 | 4 | 50 | 8.00% |
| RAMB18 | 1 | 100 | 1.00% |
| DSPs | 3 | 90 | 3.33% |
| Bonded IOB | 7 | 106 | 6.60% |

## Timing

| Metric | Result |
|---|---:|
| Clock period | 10.000 ns |
| Frequency | 100 MHz |
| WNS | +0.489 ns |
| TNS | 0.000 ns |
| Failing endpoints | 0 |
| Status | PASS |

## Timing Closure Notes

The board-ready design uses a streaming architecture instead of a large activation-memory buffer.

A major timing issue came from computing the total number of output windows directly from image_width and image_height and immediately using that result in control logic. This was fixed by pipelining:

1. total window count
2. total window multiply operands

After this, the full board-top design met 100 MHz timing.

## Hardware Bring-Up Status

The design synthesizes, places, routes, and meets timing.

Final bitstream generation requires board-specific XDC constraints for:

- clk
- rst_n
- uart_rx
- uart_tx
- led_busy
- led_done
- led_error
