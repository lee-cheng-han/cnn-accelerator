# Performance and Implementation Results

## Target

| Item | Value |
|---|---|
| Board | Digilent Arty Z7-20 |
| SoC | Xilinx Zynq-7000 |
| Part | `xc7z020clg400-1` |
| Toolchain | Vivado / Vitis 2025.2 |
| Build Type | Implemented bitstream |

## Build Status

| Item | Result |
|---|---|
| Vivado project generation | Passing |
| Bitstream generation | Passing |
| Timing | Met |
| XSA export | Passing |
| Vitis bare-metal app build | Passing |

## FPGA Utilization

Latest implemented design:

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 6,692 | 53,200 | 12.58% |
| Slice Registers | 8,058 | 106,400 | 7.57% |
| Block RAM Tile | 2 | 140 | 1.43% |
| DSPs | 1 | 220 | 0.45% |

## Timing Result

```text
All user specified timing constraints are met.
Clock = 125.000 MHz
WNS = 0.265 ns
WHS = 0.018 ns
```

## Generated Outputs

| Output | Path |
|---|---|
| Bitstream | `build/arty_z7_20_cnn/arty_z7_20_cnn.runs/impl_1/system_wrapper.bit` |
| Timing Report | `build/arty_z7_20_bitstream_timing.rpt` |
| Utilization Report | `build/arty_z7_20_bitstream_util.rpt` |
| XSA | `build/arty_z7_20_cnn/arty_z7_20_cnn.xsa` |
| Bare-metal ELF | `build/vitis_ws/cnn_baremetal/build/cnn_baremetal.elf` |
| BOOT.BIN | `build/BOOT.BIN` |
| Flow Report | `build/flow_report.md` |

## Notes

The current implementation fits comfortably on the Arty Z7-20 and leaves room for larger buffers, DMA support, additional output channels, and more compute parallelism.
