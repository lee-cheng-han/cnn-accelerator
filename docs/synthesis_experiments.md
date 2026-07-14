# PC/PK Synthesis Experiments

Target: Digilent Zybo Z7-20 (`xc7z020clg400-1`) at 125 MHz.

These are out-of-context post-synthesis estimates for the parallel compute slice: MAC array, partial-sum accumulator, and parallel post-processing. They are not full-accelerator or implementation measurements; see [top_implementation.md](top_implementation.md) for the current full-top experiment.

| PC | PK | MACs/cycle | Peak GMAC/s at 125 MHz | WNS (ns) | Est. Fmax (MHz) | LUTs | Registers | BRAM tiles | DSPs | Timing |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 2 | 8 | 16 | 2.000 | 4.909 | 323.5 | 2,858 | 650 | 0 | 0 | Met |
| 4 | 4 | 16 | 2.000 | 4.158 | 260.3 | 2,042 | 458 | 0 | 0 | Met |
| 4 | 8 | 32 | 4.000 | 4.158 | 260.3 | 4,082 | 914 | 0 | 0 | Met |

## Interpretation

`PC=4, PK=8` is the recommended baseline among timing-clean configurations because it provides 32 MACs/cycle at an estimated 260.3 MHz post-synthesis Fmax.

These results intentionally isolate the hardware that `PC/PK` changes. Replicated-bank BRAM-style activation and weight scratchpad primitives are now present, and the tiled compute engines include fetch/capture/issue staging plus scratchpad request/data ports for registered operands. The stream-loaded multi-layer path writes packetized input activations and per-layer weights into banked scratchpads, can stream intermediate layer outputs into feature scratchpads, and can stream final RGB pixels directly to the AXI output with backpressure. Full-frame mirrors remain available for scoreboarding and existing directed tests, but the board-facing top disables the large scheduler/output mirrors. Vivado maps the current signed INT8 multipliers into LUT fabric in this isolated design, which explains the zero DSP count. The current full-top smoke experiment now fits, routes, and meets the 125 MHz target; the first Zynq block-design implementation also generates a 125 MHz timing-clean bitstream and XSA.

Regenerate:

```bash
make synth-sweep
```
