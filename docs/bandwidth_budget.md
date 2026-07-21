# Compute and DDR Bandwidth Budget

This budget separates arithmetic peak from useful and memory-sustained
throughput. It is an architectural planning bound, not measured board data.

## Interface Ceiling

A 32-bit transfer on every 125 MHz AXI beat carries:

```text
4 bytes/beat * 125,000,000 beats/s = 500 MB/s = 476.8 MiB/s
```

Protocol gaps, DDR arbitration, DMA setup, tile headers, and simultaneous reads
and writes reduce sustainable application bandwidth. Final claims therefore
use measured DMA throughput rather than this ceiling.

## Worked 3x3 Layer

For one 1024x1024, `16 -> 16`, 3x3 convolution:

```text
MACs = 1024 * 1024 * 16 * 16 * 9 = 2,415,919,104
ideal time at 4 GMAC/s = 0.604 seconds
input tensor = 16 MiB
output tensor = 16 MiB
minimum tensor traffic = 32 MiB
minimum sustained bandwidth = 53.0 MiB/s
```

With 16x16 output tiles, each interior tile reads an 18x18x16 halo-inclusive
input region and writes a 16x16x16 output region. Across 4,096 tiles this is
approximately 36.25 MiB, or 60.0 MiB/s at the ideal compute time. Boundary
tiles are no larger. Weights and postprocessing parameters are loaded once per
layer and retained, not fetched for every tile.

This 3x3 case is compute-bound if tile reuse works as specified.

## Worked 1x1 Layer

For one 1024x1024, `16 -> 16`, 1x1 convolution:

```text
MACs = 1024 * 1024 * 16 * 16 = 268,435,456
ideal time at 4 GMAC/s = 0.0671 seconds
minimum tensor traffic = 32 MiB
required bandwidth = 476.8 MiB/s
```

That equals the ideal 32-bit AXI ceiling before overhead, so the 4 GMAC/s
configuration cannot sustain arithmetic peak on this workload through one
such memory path. The final `PC=4`, `PK=8` selection is therefore conditional
on measured DDR/DMA bandwidth, tiling efficiency, and full-design timing.

## Channel-Tail Policy

V1 uses tail masks and does not add cross-pixel channel packing. This keeps
operand routing and accumulator ownership deterministic.

For the board configuration `PC=2`, `PK=4`:

| Layer shape | Limiting tail | Useful lane utilization |
|---|---|---:|
| `3 -> 16` | input channels | 3 of 4 input-lane slots = 75% |
| `16 -> 16` | none | 100% |
| `16 -> 3` | output channels | 3 of 4 output lanes = 75% |

Reports distinguish raw peak, tail-adjusted useful throughput, and measured
end-to-end throughput. Channel packing may be reconsidered only after the V1
tiled implementation is stable.
