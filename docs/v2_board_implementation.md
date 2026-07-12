# V2 Arty Z7-20 Board Implementation

This is the first full Vivado board implementation for the v2 image-to-image CNN path. It integrates the v2 AXI-Lite/AXI-Stream RTL top into a Zynq block design with PS7, AXI DMA, AXI interconnects, reset generation, and a 125 MHz PL clock.

The design is board-implementation-ready evidence. The v2 bare-metal software now programs the v2 register map, sends the packetized tensor job through AXI DMA, reads back the output stream, and checks it against the golden tensor data; see [v2_baremetal_app.md](v2_baremetal_app.md).

## Configuration

| Field | Value |
|---|---:|
| Project | `arty_z7_20_cnn_v2` |
| Part | `xc7z020clg400-1` |
| Board clock | 125.000 MHz |
| PL top | `cnn_image2image_system_bd_wrapper` |
| V2 compute config | `PC=2`, `PK=4`, `MAX_CIN=16`, `MAX_COUT=16`, `MAX_PIXELS=16` |
| AXI-Lite base | `0x43C00000` |
| AXI DMA base | `0x40400000` |

## Timing

| Metric | Value |
|---|---:|
| WNS | 0.011 ns |
| TNS | 0.000 ns |
| WHS | 0.023 ns |
| THS | 0.000 ns |
| Timing met | True |

## Utilization

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 6,355 | 53,200 | 11.95% |
| Slice Registers | 7,568 | 106,400 | 7.11% |
| Block RAM Tile | 29 | 140 | 20.71% |
| DSPs | 5 | 220 | 2.27% |

## Artifacts

- Vivado project: `build/arty_z7_20_cnn_v2/arty_z7_20_cnn_v2.xpr`
- Bitstream: `build/arty_z7_20_cnn_v2/arty_z7_20_cnn_v2.runs/impl_1/system_wrapper.bit`
- XSA: `build/arty_z7_20_cnn_v2/arty_z7_20_cnn_v2.xsa`
- V2 bare-metal ELF: `build/vitis_ws_v2/cnn_v2_baremetal/build/cnn_v2_baremetal.elf`
- V2 FSBL: `build/vitis_ws_v2/arty_z7_20_cnn_v2_platform/zynq_fsbl/build/fsbl.elf`
- Timing report: `build/arty_z7_20_v2_bitstream_timing.rpt`
- Utilization report: `build/arty_z7_20_v2_bitstream_util.rpt`

## Regenerate

```bash
make v2-arty-z7-project
make v2-arty-z7-bitstream
make v2-arty-z7-xsa
make vitis-v2-app
```

Or run the complete v2 board implementation flow:

```bash
make full-v2-arty-z7-flow
```
