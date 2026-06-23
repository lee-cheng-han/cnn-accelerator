# INT8 Multi-Channel CNN Accelerator

This is a portfolio-ready starter CNN layer accelerator written in SystemVerilog.

Default configuration:

- Input channels: 3
- Output channels / filters: 4
- Kernel: 3x3
- Input/weights: signed INT8
- Accumulator: signed INT32
- Output: signed INT8
- Postprocess: bias, ReLU, arithmetic quantization shift, saturation
- Interface: AXI-stream-style valid/ready data path plus simple memory-mapped config registers

The accelerator computes:

```text
for each output channel:
  for each output pixel:
    acc = 0
    for each input channel:
      acc += 3x3 convolution(input_channel, weight_channel)
    acc += bias
    acc = ReLU(acc)
    acc = acc >>> quant_shift
    acc = saturate_to_int8(acc)
```

## Why this is more realistic than a simple 3x3 image filter

A basic image filter usually handles one input channel and one or two kernels. This design models an actual CNN layer by supporting multiple input channels, multiple output filters, INT8 weights/activations, INT32 accumulation, bias, ReLU, quantization, and performance counters.

Default MAC-equivalent operations per output pixel:

```text
3 input channels x 4 output channels x 9 kernel taps = 108 MAC-equivalent operations
```

## Build

```bash
make sim
make regression
```

If using Vivado:

```bash
vivado -mode batch -source scripts/synth_vivado.tcl
```


