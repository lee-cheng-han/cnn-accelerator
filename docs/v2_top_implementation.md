# V2 Top-Level Implementation Experiment

This is an out-of-context implementation experiment for the v2 image-to-image RTL top. It is not a board-ready Zynq block-design bitstream. If implementation does not fit, this report captures the post-synthesis evidence and failure reason.

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
| Implementation status | `routed_timing_failed` |

## Timing

| Metric | Value |
|---|---:|
| WNS | -3.749 ns |
| WHS | 0.154 ns |
| Estimated setup Fmax | 85.1 MHz |
| Timing met | False |

## Utilization

| Resource | Used |
|---|---:|
| Slice LUTs | 4,549 |
| Slice Registers | 3,382 |
| F7 Muxes | 27 |
| F8 Muxes | 8 |
| Block RAM Tile | 27 |
| DSPs | 5 |

## Artifacts

- Checkpoint: `build/v2_top_impl/v2_top_routed.dcp`
- Timing report: `build/v2_top_impl/timing_post_route.rpt`
- Utilization report: `build/v2_top_impl/utilization_post_route.rpt`
- Hold timing report: `build/v2_top_impl/timing_hold_post_route.rpt`
- DRC report: `build/v2_top_impl/drc_post_route.rpt`

## Interpretation

The current v2 top now fits and routes in this out-of-context smoke configuration, but it does not yet meet the 125 MHz internal clock target. The largest no-fit issue was fixed by mapping the banked weight scratchpads into explicit BRAM lane memories. The current worst setup path runs from the AXI-Lite image-width register through the scheduler output-pixel index calculation into direct streamed output-data selection.
The next board-facing step is reducing the timing-critical output index/direct-output and remaining scratchpad address/control paths, then rerunning this OOC implementation experiment before integrating `cnn_image2image_system_top` into a Zynq block design with PS, AXI DMA, resets, clocking, and physical constraints.

Regenerate:

```bash
make v2-top-impl
```

Scale the experiment explicitly when needed:

```bash
PC=4 PK=8 MAX_PIXELS=64 make v2-top-impl
```
