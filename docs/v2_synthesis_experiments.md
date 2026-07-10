# V2 PC/PK Synthesis Experiments

Target: Digilent Arty Z7-20 (`xc7z020clg400-1`) at 125 MHz.

These are out-of-context post-synthesis estimates for the v2 parallel compute slice: MAC array, partial-sum accumulator, and parallel post-processing. They are not full-accelerator or post-route measurements.

| PC | PK | MACs/cycle | Peak GMAC/s at 125 MHz | WNS (ns) | Est. Fmax (MHz) | LUTs | Registers | BRAM tiles | DSPs | Timing |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 2 | 8 | 16 | 2.000 | 4.909 | 323.5 | 2,858 | 650 | 0 | 0 | Met |
| 4 | 4 | 16 | 2.000 | 4.158 | 260.3 | 2,042 | 458 | 0 | 0 | Met |
| 4 | 8 | 32 | 4.000 | 4.158 | 260.3 | 4,082 | 914 | 0 | 0 | Met |

## Interpretation

`PC=4, PK=8` is the recommended baseline among timing-clean configurations because it provides 32 MACs/cycle at an estimated 260.3 MHz post-synthesis Fmax.

The full v2 AXI top remains dominated by simulation-oriented tensor register arrays, so these results intentionally isolate the hardware that `PC/PK` changes. Replicated-bank BRAM-style activation and weight scratchpad primitives are now present, but the full scheduler still needs to be retimed around their registered reads before the top-level v2 implementation will represent the final physical memory architecture. Vivado maps the current signed INT8 multipliers into LUT fabric in this isolated design, which explains the zero DSP count. Before carrying this baseline into the board-facing design, run the full v2 regression and confirm post-route timing in the dedicated v2 block design.

Regenerate:

```bash
make v2-synth-sweep
```
