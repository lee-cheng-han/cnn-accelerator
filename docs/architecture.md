# Architecture

The accelerator implements one INT8 CNN convolution layer.

## Dataflow

1. Software writes configuration registers.
2. Software writes 3x3 weights for every output channel and input channel.
3. Software writes one bias per output channel.
4. Software sets the start bit.
5. Input activations stream through the AXI-stream-style input port.
6. The activation buffer stores the input feature map.
7. The controller walks over every valid 3x3 output position.
8. The output channel array computes all configured output filters.
9. The selected output channel result is sent out through the AXI-stream-style output port.

## Default tensor shapes

- Input: 3 x H x W
- Weights: 4 x 3 x 3 x 3
- Bias: 4
- Output: 4 x (H-2) x (W-2)

## Output order

The output stream is pixel-major with output-channel-minor order:

```text
(row 0, col 0, oc 0)
(row 0, col 0, oc 1)
(row 0, col 0, oc 2)
(row 0, col 0, oc 3)
(row 0, col 1, oc 0)
...
```

## Current simplification

This version is intentionally a clean first implementation. It uses an activation buffer instead of fully streaming line-buffer compute. This makes the design easier to verify. The `line_buffer_3x3` and `window_generator_3x3` blocks are included for the next streaming upgrade.
