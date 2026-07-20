# Verification Matrix

## Summary

| Level | Test / artifact | Status | Notes |
|---|---|---|---|
| Source hygiene | Python syntax compile | Passing | `python3 -m py_compile` over active scripts and models |
| Source hygiene | shell syntax check | Passing | `bash -n` over active shell scripts |
| model | `tests/test_image2image_int8.py` | Passing | bit-accurate Python integer model coverage |
| default parameters | Gaussian impulse-response test | Passing | all 16 hidden channels used; residual output matches the expected 3x3 low-pass kernel |
| golden generation | `make baremetal-headers` | Passing | writes deterministic tensors and C DMA packet header |
| compute RTL | `tb_parallel_mac_array` | Covered | PC x PK signed INT8 MAC datapath |
| compute RTL | `tb_tiled_conv1x1_engine` | Covered | array-backed and banked-scratchpad-backed 1x1 operand paths |
| compute RTL | `tb_tiled_conv3x3_engine` | Covered | array-backed and banked-scratchpad-backed 3x3 operand paths |
| tensor RTL | `tb_tensor_address_gen` | Covered | stride, padding, and valid/invalid address behavior |
| tensor RTL | `tb_banked_scratchpads` | Covered | one-cycle replicated-bank activation/weight scratchpad reads |
| scheduler RTL | `tb_single_layer_scheduler` | Covered | full-image array-backed and banked-scratchpad-backed scheduler paths |
| controller RTL | `tb_full_network_golden_flow` | Covered | full 3-layer denoising controller against Python golden tensors |
| stream RTL | `tb_stream_loaded_full_network_golden_flow` | Covered | packet-loaded full network with output backpressure |
| AXI stream RTL | `tb_axi_stream_full_network_golden_flow` | Covered | seven-packet AXI job, malformed packet cases, repeated starts, and output compare |
| implementation | `make full-zybo-z7-flow` | Passing | Zynq block design, bitstream, and XSA generated at 125 MHz |
| software | `make vitis-app` | Passing | golden tensor AXI DMA app and FSBL build from XSA |
| boot package | `make boot-image` | Passing | packages `build/BOOT.BIN` |
| Board | Zybo Z7-20 UART PASS | Pending | requires physical board |

## Feature Coverage

| Feature | Current confidence | Evidence |
|---|---|---|
| INT8 arithmetic | High | Python model tests and RTL MAC/engine tests |
| 1x1 convolution | High | tiled engine tests and scheduler tests |
| 3x3 convolution | High | address generator, tiled engine, scheduler, and full-network golden tests |
| runtime channel tails | High | directed PC/PK tail cases |
| bias, ReLU, quantization, saturation | High | Python model and compute/post-processing RTL tests |
| stream-loaded activations/weights/biases | High | stream-loaded full-network golden flow |
| seven-packet AXI tensor job | High | AXI stream full-network golden flow |
| output backpressure | High | stream-loaded and AXI stream golden flows |
| AXI-Lite control/status/performance registers | High pre-board | integrated system wrapper and Vitis app build against exported XSA |
| Zynq block design integration | High pre-board | bitstream and XSA generated at 125 MHz |
| bare-metal DMA integration | High pre-board | Vitis app and BOOT.BIN build from XSA |
| real hardware behavior | Pending | board not yet available |

## Main Regression Commands

```bash
make model-test
make golden-test
make unit
make regression
make full-zybo-z7-flow
make vitis-app
make boot-image
```

## Remaining Evidence For 10/10 Hardware Validation

- Capture UART output showing `[PASS] image-to-image DMA golden test passed`.
- Record measured DMA/ transfer cycles and usec from the same UART run.
- Save a board setup photo or screenshot under `docs/assets/`.
- Update `docs/performance_results.md` with measured board latency/throughput.
