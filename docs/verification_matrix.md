# Verification Matrix

## Summary

| Level | Test / artifact | Status | Notes |
|---|---|---|---|
| Source hygiene | Python syntax compile | Passing | `python3 -m py_compile` over scripts/models |
| Source hygiene | shell syntax check | Passing | `bash -n` over shell scripts |
| Unit RTL | `tb_mac_unit` | Covered | MAC arithmetic |
| Unit RTL | `tb_mac_array_3x3` | Covered | 3x3 MAC array behavior |
| Unit RTL | `tb_channel_accumulator` | Covered | channel sum behavior |
| Unit RTL | `tb_conv_engine` | Covered | convolution/post-processing behavior |
| Unit RTL | `tb_line_buffer_3x3` | Covered | line-buffer behavior |
| Unit RTL | `tb_v2_banked_scratchpads` | Covered | one-cycle replicated-bank BRAM-style activation/weight scratchpad reads |
| Unit RTL | `tb_window_generator_3x3` | Covered | window tap ordering |
| Unit RTL | `tb_streaming_window_buffer` | Covered | streaming 3x3 window generation |
| Unit RTL | `tb_cnn_config_loader` | Covered | config, weight, and bias loading |
| Stream adapter | `tb_axis_rgb_to_channels` | Covered | packed RGB to R/G/B samples |
| Stream adapter | `tb_axis_output_widen` | Covered | signed int8 to sign-extended int32 |
| Core RTL | `tb_streaming_cnn_core` | Covered | directed 1x1/3x3 cases |
| Core RTL | `tb_streaming_cnn_core_random` | Covered | randomized core cases |
| Legacy top | `tb_cnn_accel_top_small` | Covered | earlier non-DMA top |
| Legacy top | `tb_cnn_accel_top_random` | Covered | earlier non-DMA randomized top |
| AXI-Lite | `tb_cnn_axi_lite_slave` | Covered | register reads/writes |
| AXI-Lite system | `tb_cnn_axi_system_top` | Covered | legacy AXI-Lite system path |
| Current DMA system | `tb_cnn_dma_system_top` | Passing | 3x3 and 1x1 DMA-style simulation |
| Implementation | Vivado bitstream | Passing | timing met |
| Software | Vitis bare-metal ELF | Passing | build complete |
| Board | Arty Z7-20 UART PASS | Pending | requires physical board |

## DMA Top Simulation Coverage

`tb/stream/tb_cnn_dma_system_top.sv` verifies:

| Behavior | Covered |
|---|---|
| AXI-Lite width/height writes | Yes |
| AXI-Lite mode flag writes | Yes |
| AXI-Lite weight writes | Yes |
| AXI-Lite bias writes | Yes |
| start/clear control flow | Yes |
| packed RGB input beats | Yes |
| `axis_rgb_to_channels` integration | Yes |
| 3x3 valid convolution | Yes |
| 1x1 convolution | Yes |
| output-channel order | Yes |
| sign-extended 32-bit output | Yes |
| final TLAST | Yes |

Expected passing output:

```text
[TEST] DMA top 3x3 mode
[TEST] DMA top 1x1 mode
[PASS] tb_cnn_dma_system_top tests=80
```

The checked-in proof log is `docs/logs/dma_top_sim_pass.log`.

## Feature Coverage

| Feature | Current confidence | Evidence |
|---|---|---|
| 1x1 mode | High | core tests and DMA top test |
| 3x3 mode | High | window-buffer tests, core tests, DMA top test |
| bias add | Medium | `conv_engine` and config-loader tests |
| ReLU | Medium | `conv_engine` and generated mode flag usage |
| quantization shift | Medium | `conv_engine` tests and register support |
| saturation | Medium | `conv_engine` post-processing tests |
| AXI-Lite protocol | Medium | directed AXI-Lite testbench |
| AXI-Stream input backpressure | Medium | adapter/core ready-valid tests |
| AXI-Stream output backpressure | Medium | output widening and core FIFO behavior |
| DMA block design | High pre-board | XSA address/connectivity checks |
| real hardware behavior | Pending | board not yet available |

## Gaps To Close Before A 10/10 Portfolio Version

- Add generated random images and random weights compared against a Python golden model.
- Add coverage-style reporting for mode, image size, ReLU, bias, quantization, saturation, and stall scenarios.
- Capture board UART PASS log once hardware arrives.
