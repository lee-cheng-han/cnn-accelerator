# Performance and Implementation Results

## Target

| Item | Value |
|---|---|
| Board | Digilent Zybo Z7-20 |
| SoC | Xilinx Zynq-7000 |
| Part | `xc7z020clg400-1` |
| Toolchain | Vivado / Vitis 2025.2 |
| Build Type | implemented Zynq block-design bitstream |

## Build Status

| Item | Result |
|---|---|
| Vivado project generation | Passing |
| bitstream generation | Passing |
| Timing | Met at 125 MHz |
| XSA export | Passing |
| bare-metal app build | Passing |
| BOOT.BIN packaging | Available through `make boot-image` |

## FPGA Utilization

Latest board implementation:

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 7,438 | 53,200 | 13.98% |
| Slice Registers | 7,601 | 106,400 | 7.14% |
| Block RAM Tile | 29 | 140 | 20.71% |
| DSPs | 4 | 220 | 1.82% |

## Timing Result

```text
All user specified timing constraints are met.
Clock = 125.000 MHz
WNS = 0.084 ns
WHS = 0.020 ns
```

## Compute Snapshot

The implemented board smoke configuration is `PC=2`, `PK=4`, `MAX_PIXELS=16`.

The compute sweep also documents the scaling target:

| PC | PK | MACs/cycle | Peak GMAC/s at 125 MHz | Timing |
|---:|---:|---:|---:|---|
| 4 | 8 | 32 | 4.000 | Met out-of-context |

## Generated Outputs

| Output | Path |
|---|---|
| Bitstream | `build/zybo_z7_20_cnn/zybo_z7_20_cnn.runs/impl_1/system_wrapper.bit` |
| Timing Report | `build/zybo_z7_20_bitstream_timing.rpt` |
| Utilization Report | `build/zybo_z7_20_bitstream_util.rpt` |
| XSA | `build/zybo_z7_20_cnn/zybo_z7_20_cnn.xsa` |
| Bare-metal ELF | `build/vitis_ws/cnn_baremetal/build/cnn_baremetal.elf` |
| BOOT.BIN | `build/BOOT.BIN` |
| Flow Report | `build/flow_report.md` |

## Notes

The current implementation fits comfortably on the Zybo Z7-20 in the board smoke configuration and leaves room for an ILA/debug variant and future scaling toward the `PC=4`, `PK=8` compute target.
