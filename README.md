# Configurable INT8 CNN Accelerator

A configurable CNN convolution accelerator written in SystemVerilog. The design supports both **1×1** and **3×3** convolution modes, INT8 activations and weights, INT32 accumulation, bias addition, ReLU, quantization shifting, output saturation, AXI-style streaming I/O, memory-mapped configuration registers, and performance counters.

This project is intended as a portfolio-quality RTL design project for FPGA, ASIC, and digital IC design roles.

---

## Features

* Configurable **1×1 convolution** and **3×3 convolution**
* INT8 signed input activations
* INT8 signed weights
* INT32 signed accumulation
* Multiple input channels
* Multiple output channels
* Bias addition
* ReLU activation
* Arithmetic right-shift quantization
* INT8 output saturation
* AXI-style streaming input interface
* AXI-style streaming output interface
* Memory-mapped configuration registers
* Performance counters:
  * input pixel count
  * output pixel count
  * generated window count
  * MAC count
* Directed SystemVerilog testbenches
* Randomized SystemVerilog testbenches
* Vivado XSim simulation flow
* Vivado synthesis and timing flow

---

## Architecture Overview

The accelerator processes streamed image data and produces streamed convolution outputs. The design is split into control, buffering, compute, post-processing, and stream interface blocks.

```text
Input Stream
    |
    v
AXI-style Input Interface
    |
    v
Activation / Line Buffer
    |
    v
3x3 Window Generator
    |
    v
Convolution Engine
    |
    +--> 1x1 mode: uses tap 0 only
    |
    +--> 3x3 mode: uses all 9 taps
    |
    v
Bias / ReLU / Quantization / Saturation
    |
    v
AXI-style Output Interface
    |
    v
Output Stream
```

---

## Convolution Modes

The accelerator supports two kernel modes through a configuration register bit.

```text
kernel_mode = 0 -> 1x1 convolution
kernel_mode = 1 -> 3x3 convolution
```

### 1×1 Mode

In 1×1 mode, the accelerator keeps the full input spatial size.

```text
Output height = input height
Output width  = input width
MACs per output pixel = input_channels × output_channels
```

Only kernel tap `0` is used.

### 3×3 Mode

In 3×3 mode, the accelerator performs valid convolution.

```text
Output height = input height - 2
Output width  = input width - 2
MACs per output pixel = input_channels × output_channels × 9
```

All 9 kernel taps are used.

---

## Configuration Register Map

| Address   | Register     | Description               |
| --------- | ------------ | ------------------------- |
| `0x0000`  | CONTROL      | Start and feature enables |
| `0x0008`  | IMAGE_WIDTH  | Input image width         |
| `0x000C`  | IMAGE_HEIGHT | Input image height        |
| `0x0010`  | QUANT_SHIFT  | Quantization right shift  |
| `0x0100+` | WEIGHTS      | Convolution weights       |
| `0x0400+` | BIAS         | Bias values               |

### CONTROL Register

| Bit | Name           | Description               |
| --- | -------------- | ------------------------- |
| 0   | `start`        | Start accelerator         |
| 1   | `relu_enable`  | Enable ReLU               |
| 2   | `bias_enable`  | Enable bias addition      |
| 3   | `quant_enable` | Enable quantization shift |
| 4   | `kernel_mode`  | `0 = 1x1`, `1 = 3x3`      |

Example:

```systemverilog
// Start 3x3 convolution with ReLU, bias, and quantization enabled
ctrl = {27'd0, 1'b1, quant_enable, bias_enable, relu_enable, 1'b1};

// Start 1x1 convolution with ReLU, bias, and quantization enabled
ctrl = {27'd0, 1'b0, quant_enable, bias_enable, relu_enable, 1'b1};
```

---

## Repository Structure

```text
cnn_accelerator/
├── rtl/
│   ├── cnn_accel_pkg.sv
│   ├── cnn_accel_top.sv
│   ├── control/
│   │   ├── accel_controller.sv
│   │   ├── config_regs.sv
│   │   └── perf_counters.sv
│   ├── stream/
│   │   ├── axis_input_if.sv
│   │   ├── axis_output_if.sv
│   │   └── stream_fifo.sv
│   ├── buffer/
│   │   ├── activation_buffer.sv
│   │   ├── weight_buffer.sv
│   │   ├── line_buffer_3x3.sv
│   │   └── window_generator_3x3.sv
│   ├── compute/
│   │   ├── mac_unit.sv
│   │   ├── mac_array_3x3.sv
│   │   ├── adder_tree.sv
│   │   ├── channel_accumulator.sv
│   │   ├── conv_engine.sv
│   │   └── output_channel_array.sv
│   └── postprocess/
│       ├── bias_add.sv
│       ├── relu.sv
│       ├── quantizer.sv
│       └── output_saturate.sv
│
├── tb/
│   ├── tb_mac_unit.sv
│   ├── tb_mac_array_3x3.sv
│   ├── tb_channel_accumulator.sv
│   ├── tb_window_generator_3x3.sv
│   ├── tb_conv_engine.sv
│   ├── tb_cnn_accel_top_small.sv
│   └── tb_cnn_accel_top_random.sv
│
├── scripts/
│   ├── run_xsim_tb.sh
│   ├── run_iverilog_tb.sh
│   └── clean.sh
│
├── synth_out/
├── Makefile
└── README.md
```

---

## Main RTL Modules

### `cnn_accel_top.sv`

Top-level accelerator wrapper. Connects the configuration registers, controller, buffers, convolution engine, output stream interface, and performance counters.

### `config_regs.sv`

Memory-mapped configuration register block. Stores image dimensions, quantization shift, feature enables, kernel mode, weights, and bias values.

### `accel_controller.sv`

Controls accelerator execution. Tracks output coordinates, output dimensions, output completion, and mode-dependent behavior for 1×1 and 3×3 convolution.

### `conv_engine.sv`

Main convolution datapath. Multiplies input window values by weights, accumulates across input channels, and supports mode-dependent accumulation:

```text
1x1 mode -> use only tap 0
3x3 mode -> use all 9 taps
```

### `perf_counters.sv`

Tracks runtime statistics such as input pixels, output pixels, convolution windows, and MAC operations.

---

## Verification

The project includes directed and randomized SystemVerilog testbenches.

### Unit Tests

| Testbench                    | Purpose                                                                |
| ---------------------------- | ---------------------------------------------------------------------- |
| `tb_mac_unit.sv`             | Verifies signed INT8 multiply behavior                                 |
| `tb_mac_array_3x3.sv`        | Verifies 3×3 MAC array behavior                                        |
| `tb_channel_accumulator.sv`  | Verifies accumulation across input channels                            |
| `tb_window_generator_3x3.sv` | Verifies window generation                                             |
| `tb_conv_engine.sv`          | Verifies convolution datapath, post-processing, 1×1 mode, and 3×3 mode |

### Top-Level Tests

| Testbench                    | Purpose                                                                                           |
| ---------------------------- | ------------------------------------------------------------------------------------------------- |
| `tb_cnn_accel_top_small.sv`  | Directed end-to-end accelerator tests                                                             |
| `tb_cnn_accel_top_random.sv` | Randomized end-to-end accelerator tests with stalls, gaps, reset recovery, 1×1 mode, and 3×3 mode |

The testbenches verify:

* signed arithmetic correctness
* 1×1 convolution correctness
* 3×3 convolution correctness
* bias addition
* ReLU
* quantization shift
* INT8 saturation
* output ordering
* `tlast` behavior
* AXI-style backpressure
* input/output counters
* window counters
* MAC counters
* reset recovery

---

## Running Simulation

Run a single testbench:

```bash
make xsim TB=tb_conv_engine SEED=12345
```

Run the directed top-level test:

```bash
make xsim TB=tb_cnn_accel_top_small SEED=12345
```

Run the randomized top-level test:

```bash
make xsim TB=tb_cnn_accel_top_random SEED=12345
```

Run the full regression:

```bash
make regression SEED=12345
```

---

## Lint

Run lint checks:

```bash
make lint
```

---

## Synthesis

Run synthesis:

```bash
make synth
```

Check timing:

```bash
grep -A 20 "Design Timing Summary" synth_out/timing_summary.rpt
```

A passing timing result should show:

```text
WNS >= 0
TNS = 0
Failing Endpoints = 0
```

---

## Current Verification Status

Latest known project status:

```text
Directed unit tests: PASS
Convolution engine 1x1 tests: PASS
Convolution engine 3x3 tests: PASS
Directed top-level 1x1 test: PASS
Directed top-level 3x3 tests: PASS
Randomized top-level 1x1 test: PASS
Randomized top-level 3x3 tests: PASS
```

Final signoff commands:

```bash
make regression SEED=12345
make lint
make synth
grep -A 20 "Design Timing Summary" synth_out/timing_summary.rpt
```
