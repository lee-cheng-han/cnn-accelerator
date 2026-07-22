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
| WNS | 0.261 ns |
| WHS | 0.083 ns |
| Estimated setup Fmax | 129.2 MHz |
| Timing met | True |

### Timing robustness

The 125 MHz target was implemented twice from clean synthesis using different placement and routing directives. Both variants use post-route `phys_opt_design -directive AggressiveExplore`.

| Variant | Place | Route | WNS | WHS |
|---|---|---|---:|---:|
| Canonical | Default | Default | 0.261 ns | 0.083 ns |
| Alternate | Explore | Explore | 0.310 ns | 0.083 ns |

Both runs converge on metadata-index address generation into the quantization descriptor BRAM as the limiting setup path. The convolution post-processing, weight-scratchpad addressing, residual output, and activation-scratchpad paths were explicitly registered or simplified and no longer appear as the worst path.

## Utilization

| Resource | Used |
|---|---:|
| Slice LUTs | 6,053 |
| Slice Registers | 5,248 |
| F7 Muxes | 86 |
| F8 Muxes | 33 |
| Block RAM Tile | 33 |
| DSPs | 4 |

## Artifacts

- Checkpoint: `build/top_impl/top_routed.dcp`
- Timing report: `build/top_impl/timing_post_route.rpt`
- Utilization report: `build/top_impl/utilization_post_route.rpt`
- Hold timing report: `build/top_impl/timing_hold_post_route.rpt`
- DRC report: `build/top_impl/drc_post_route.rpt`

## Interpretation

The current top fits, routes, and meets the 125 MHz internal clock target in this out-of-context smoke configuration.
The next board-facing step is integrating `cnn_image2image_system_top` into a Zynq block design with PS, AXI DMA, resets, clocking, physical constraints, and board-level timing evidence.

Regenerate:

```bash
make top-impl
```

Scale the experiment explicitly when needed:

```bash
PC=4 PK=8 MAX_PIXELS=64 make top-impl
```
