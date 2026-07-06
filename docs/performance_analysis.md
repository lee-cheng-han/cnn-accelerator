# Performance Analysis

## Target

| Item | Value |
|---|---|
| Board | Digilent Arty Z7-20 |
| FPGA part | `xc7z020clg400-1` |
| PL clock | 125 MHz |
| Input format | one 32-bit packed RGB pixel per AXI DMA MM2S beat |
| Output format | one signed result per 32-bit AXI DMA S2MM beat |
| CNN channels | 3 input channels, 4 output channels |
| Arithmetic | signed int8 x signed int8, signed int32 accumulation |

## Output Counts

| Mode | Output windows / pixels | Output words |
|---|---:|---:|
| 1x1 | `width * height` | `width * height * 4` |
| 3x3 valid | `(width - 2) * (height - 2)` | `(width - 2) * (height - 2) * 4` |

For an 8x8 image:

| Mode | Output windows / pixels | Output words |
|---|---:|---:|
| 1x1 | 64 | 256 |
| 3x3 valid | 36 | 144 |

## Compute Structure

The current `streaming_cnn_core` feeds one output channel at a time through a shared `conv_engine`.

For each output window/pixel:

- Four output channels are computed sequentially.
- The convolution engine is internally pipelined.
- The output FIFO absorbs short downstream stalls.

This keeps resource use low and makes timing easier, at the cost of lower peak parallelism than a fully unrolled four-output-channel datapath.

## Operation Counts

Per output window:

| Mode | Multiplications per output channel | Output channels | MAC-like multiplies per window |
|---|---:|---:|---:|
| 1x1 | 3 | 4 | 12 |
| 3x3 | 27 | 4 | 108 |

For an 8x8 image:

| Mode | Windows / pixels | Total MAC-like multiplies |
|---|---:|---:|
| 1x1 | 64 | 768 |
| 3x3 valid | 36 | 3,888 |

## Resource Results

Latest documented implementation:

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 6,692 | 53,200 | 12.58% |
| Slice registers | 8,058 | 106,400 | 7.57% |
| Block RAM tile | 2 | 140 | 1.43% |
| DSPs | 1 | 220 | 0.45% |

Timing:

```text
All user specified timing constraints are met.
Clock = 125.000 MHz
WNS = 0.265 ns
WHS = 0.018 ns
```

## Bottlenecks

The main throughput bottlenecks are intentional for this bring-up design:

- Output channels are computed sequentially through one shared convolution engine.
- Input pixels are expanded from one RGB beat into three channel samples.
- Weights are loaded over AXI-Lite rather than streamed from memory.
- The bare-metal software uses polling instead of interrupts.

These choices reduce complexity and make board bring-up easier.

## Scaling Plan

Most useful scaling steps:

1. Parallelize output channels by instantiating multiple `conv_engine` blocks.
2. Load weights through DMA for larger networks.
3. Expose hardware performance counters to software.
4. Add stride/padding to avoid software-side shape assumptions.
5. Add multi-layer sequencing or a small command descriptor format.

## Interview Talking Points

- The design trades peak throughput for integration clarity and low resource use.
- Only 1 DSP is used, leaving large headroom on the Arty Z7-20.
- The valid 3x3 mode reduces output dimensions by two in each spatial direction.
- The generated identity-style weights make hardware bring-up easy because expected values are visually inspectable.
- The next performance step would be output-channel parallelism, not a faster AXI-Lite path, because bulk image data already moves over AXI DMA.
