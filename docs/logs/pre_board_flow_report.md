# Pre-Board Flow Report

Generated: 2026-07-20 04:27:49

## Artifacts

| Artifact | Status | Path |
|---|---|---|
| Bitstream | present | `build/zybo_z7_20_cnn/zybo_z7_20_cnn.runs/impl_1/system_wrapper.bit` |
| Vivado-exported XSA | present | `build/zybo_z7_20_cnn/zybo_z7_20_cnn.xsa` |
| Vitis platform | present | `build/vitis_ws/zybo_z7_20_cnn_platform/export/zybo_z7_20_cnn_platform/zybo_z7_20_cnn_platform.xpfm` |
| Bare-metal ELF | present | `build/vitis_ws/cnn_baremetal/build/cnn_baremetal.elf` |
| FSBL | present | `build/vitis_ws/zybo_z7_20_cnn_platform/zynq_fsbl/build/fsbl.elf` |
| BOOT.BIN | present | `build/BOOT.BIN` |
| Golden DMA header | present | `software/zynq_baremetal/generated/golden_dma_job.h` |

## Timing

| Metric | Value |
|---|---:|
| Clock | 125.000 MHz |
| Period | 8.000 ns |
| WNS | 0.084 ns |
| TNS | 0.000 ns |
| Failing setup endpoints | 0 |
| WHS | 0.020 ns |
| THS | 0.000 ns |
| Failing hold endpoints | 0 |
| Constraints met | True |

## Utilization

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 7438 | 53200 | 13.98% |
| Slice Registers | 7601 | 106400 | 7.14% |
| Block RAM Tile | 29 | 140 | 20.71% |
| DSPs | 4 | 220 | 1.82% |

## Next Hardware Evidence

- UART log with `[PASS] image-to-image DMA golden test passed`.
- Photo or screenshot of programmed Zybo Z7-20 setup.
- Measured board latency/throughput and printed performance counters.
- Any ILA or debug capture used during first bring-up.
