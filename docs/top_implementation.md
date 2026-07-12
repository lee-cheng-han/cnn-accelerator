# Top-Level Implementation Experiment

This is an out-of-context implementation experiment for the image-to-image RTL top. It is not a board-ready Zynq block-design bitstream. If implementation does not fit, this report captures the post-synthesis evidence and failure reason.

## Configuration

| Field | Value |
|---|---:|
| Part | `xc7z020clg400-1` |
| Top | `cnn_image2image_system_top` |
| PC | 2 |
| PK | 4 |
| MAX_CIN | 16 |
| MAX_COUT | 16 |
| MAX_PIXELS | 16 |
| Clock target | 125.000 MHz (8.000 ns) |
| Result stage | `post_route` |
| Implementation status | `passed` |

## Timing

| Metric | Value |
|---|---:|
| WNS | 0.020 ns |
| WHS | 0.094 ns |
| Estimated setup Fmax | 125.3 MHz |
| Timing met | True |

## Utilization

| Resource | Used |
|---|---:|
| Slice LUTs | 4,415 |
| Slice Registers | 4,059 |
| F7 Muxes | 25 |
| F8 Muxes | 8 |
| Block RAM Tile | 27 |
| DSPs | 5 |

## Artifacts

- Checkpoint: `build/top_impl/top_routed.dcp`
- Timing report: `build/top_impl/timing_post_route.rpt`
- Utilization report: `build/top_impl/utilization_post_route.rpt`
- Hold timing report: `build/top_impl/timing_hold_post_route.rpt`
- DRC report: `build/top_impl/drc_post_route.rpt`

## Interpretation

The current top fits, routes, and meets the 125 MHz internal clock target in this out-of-context smoke configuration.
The Zynq block-design implementation has also been generated and routed with board-level timing evidence; see [board_implementation.md](board_implementation.md).

Regenerate:

```bash
make top-impl
```

Scale the experiment explicitly when needed:

```bash
PC=4 PK=8 MAX_PIXELS=64 make top-impl
```
