# Verification Plan

## Unit tests

- `tb_mac_unit.sv`: signed multiply-accumulate behavior and enable gating.
- `tb_mac_array_3x3.sv`: nine parallel signed products.
- `tb_channel_accumulator.sv`: accumulation across input channels.
- `tb_conv_engine.sv`: 3-channel 3x3 convolution, bias, ReLU, quantization, saturation.
- `tb_line_buffer_3x3.sv`: validates 3x3 window count for a 5x5 image.
- `tb_window_generator_3x3.sv`: validates tap packing.

## Top-level test

- `tb_cnn_accel_top_small.sv`: configures a 5x5x3 input, four filters, streams activations, and checks every output against a testbench golden calculation.

## Future randomized test

- `models/generate_vectors.py` generates randomized input, weights, bias, and expected outputs.
- `tb_cnn_accel_top_random.sv` is a placeholder for loading `.mem` files and checking against generated vectors.
