# Synthesis and Implementation Results

## Target Configuration

| Item | Value |
|---|---|
| Board | Digilent Arty Z7-20 |
| FPGA Part | `xc7z020clg400-1` |
| Top-Level Wrapper | `system_wrapper` |
| Vivado Version | 2025.2 |
| Design Flow | Script-generated Vivado project and block design |

## Implementation Status

| Stage | Result |
|---|---|
| Vivado project creation | Passing |
| Block design validation | Passing |
| Synthesis | Passing |
| Implementation | Passing |
| Bitstream generation | Passing |
| Timing | Met |
| XSA export | Passing |

## Resource Utilization

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 5,678 | 53,200 | 10.67% |
| Slice Registers | 7,749 | 106,400 | 7.28% |
| Block RAM Tile | 4.5 | 140 | 3.21% |
| RAMB36/FIFO | 4 | 140 | 2.86% |
| RAMB18 | 1 | 280 | 0.36% |
| DSPs | 3 | 220 | 1.36% |

## Timing Summary

```text
All user specified timing constraints are met.
```

## Important Generated Files

| File | Description |
|---|---|
| `build/arty_z7_20_cnn/arty_z7_20_cnn.xpr` | Generated Vivado project |
| `build/arty_z7_20_cnn/arty_z7_20_cnn.runs/impl_1/system_wrapper.bit` | Generated bitstream |
| `build/arty_z7_20_bitstream_util.rpt` | Utilization report |
| `build/arty_z7_20_bitstream_timing.rpt` | Timing report |
| `build/arty_z7_20_cnn/arty_z7_20_cnn.xsa` | Exported hardware platform |

## Warning Notes

Vivado may print board-store warnings related to unrelated board parts. These are not design failures. The project targets the raw Zynq part:

```text
xc7z020clg400-1
```

Relevant passing checks:

- synthesis completes
- implementation completes
- bitstream is generated
- timing is met
- XSA exports correctly
