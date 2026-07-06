# Pre-Board Flow Report

Generated: 2026-07-06 08:49:26

## Artifacts

| Artifact | Status | Path |
|---|---|---|
| Bitstream | present | `build/arty_z7_20_cnn/arty_z7_20_cnn.runs/impl_1/system_wrapper.bit` |
| Vivado-exported XSA | present | `build/arty_z7_20_cnn/arty_z7_20_cnn.xsa` |
| Vitis platform XSA copy | present | `build/vitis_ws/arty_z7_20_cnn_platform/hw/arty_z7_20_cnn.xsa` |
| Bare-metal ELF | present | `build/vitis_ws/cnn_baremetal/build/cnn_baremetal.elf` |
| FSBL | present | `build/vitis_ws/arty_z7_20_cnn_platform/zynq_fsbl/build/fsbl.elf` |
| BOOT.BIN | present | `build/BOOT.BIN` |
| DMA simulation proof log | present | `docs/logs/dma_top_sim_pass.log` |

## Timing

| Metric | Value |
|---|---:|
| Clock | 125.000 MHz |
| Period | 8.000 ns |
| WNS | 0.265 ns |
| TNS | 0.000 ns |
| Failing setup endpoints | 0 |
| WHS | 0.018 ns |
| THS | 0.000 ns |
| Failing hold endpoints | 0 |
| Constraints met | True |

## Utilization

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 6692 | 53200 | 12.58% |
| Slice Registers | 8058 | 106400 | 7.57% |
| Block RAM Tile | 2 | 140 | 1.43% |
| DSPs | 1 | 220 | 0.45% |

## Next Hardware Evidence

- UART log with `[PASS] CNN DMA accelerator test passed`.
- Photo or screenshot of programmed Arty Z7-20 setup.
- Measured board latency/throughput for the generated 8x8 3x3 test.
- Any ILA or debug capture used during first bring-up.
