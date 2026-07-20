# Synthesis and Implementation Results

## Target Configuration

| Item | Value |
|---|---|
| Board | Digilent Zybo Z7-20 |
| FPGA Part | `xc7z020clg400-1` |
| Top-Level Wrapper | `system_wrapper` |
| RTL Top | `cnn_image2image_system_top` |
| Vivado Version | 2025.2 |
| Design Flow | Script-generated Vivado project and Zynq block design |

## Implementation Status

| Stage | Result |
|---|---|
| Vivado project creation | Passing |
| block design validation | Passing |
| Synthesis | Passing |
| Implementation | Passing |
| Bitstream generation | Passing |
| Timing | Met at 125 MHz |
| XSA export | Passing |

## Resource Utilization

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 7,438 | 53,200 | 13.98% |
| Slice Registers | 7,601 | 106,400 | 7.14% |
| Block RAM Tile | 29 | 140 | 20.71% |
| DSPs | 4 | 220 | 1.82% |

## Timing Summary

```text
All user specified timing constraints are met.
Clock = 125.000 MHz
WNS = 0.084 ns
WHS = 0.020 ns
```

## Important Generated Files

| File | Description |
|---|---|
| `build/zybo_z7_20_cnn/zybo_z7_20_cnn.xpr` | Generated Vivado project |
| `build/zybo_z7_20_cnn/zybo_z7_20_cnn.runs/impl_1/system_wrapper.bit` | Generated bitstream |
| `build/zybo_z7_20_bitstream_util.rpt` | utilization report |
| `build/zybo_z7_20_bitstream_timing.rpt` | timing report |
| `build/zybo_z7_20_cnn/zybo_z7_20_cnn.xsa` | Exported hardware platform |

## Warning Notes

Vivado may print board-store warnings related to unrelated board parts and generated interconnect adaptation. These are tracked as generated-tool warnings, not handwritten RTL failures. The board project targets the raw Zynq part:

```text
xc7z020clg400-1
```

Relevant passing checks:

- block design validates
- synthesis completes
- implementation completes
- bitstream is generated
- timing is met
- XSA exports correctly
