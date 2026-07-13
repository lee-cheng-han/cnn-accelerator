# Arty Z7-20 Board Implementation

This is the first full Vivado board implementation for the image-to-image CNN path. It integrates the AXI-Lite/AXI-Stream RTL top into a Zynq block design with PS7, AXI DMA, AXI interconnects, reset generation, and a 125 MHz PL clock.

The design is board-implementation-ready evidence. The bare-metal software now programs the register map, sends the packetized tensor job through AXI DMA, reads back the output stream, and checks it against the golden tensor data; see [baremetal_app.md](baremetal_app.md).

## Configuration

| Field | Value |
|---|---:|
| Project | `arty_z7_20_cnn` |
| Part | `xc7z020clg400-1` |
| Board clock | 125.000 MHz |
| PL top | `cnn_image2image_system_bd_wrapper` |
| compute config | `PC=2`, `PK=4`, `MAX_CIN=16`, `MAX_COUT=16`, `MAX_PIXELS=16` |
| AXI-Lite base | `0x43C00000` |
| AXI DMA base | `0x40400000` |

## Timing

| Metric | Value |
|---|---:|
| WNS | 0.133 ns |
| TNS | 0.000 ns |
| WHS | 0.016 ns |
| THS | 0.000 ns |
| Timing met | True |

## Utilization

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 7,168 | 53,200 | 13.47% |
| Slice Registers | 7,598 | 106,400 | 7.14% |
| Block RAM Tile | 29 | 140 | 20.71% |
| DSPs | 4 | 220 | 1.82% |

## Artifacts

- Vivado project: `build/arty_z7_20_cnn/arty_z7_20_cnn.xpr`
- Bitstream: `build/arty_z7_20_cnn/arty_z7_20_cnn.runs/impl_1/system_wrapper.bit`
- XSA: `build/arty_z7_20_cnn/arty_z7_20_cnn.xsa`
- bare-metal ELF: `build/vitis_ws/cnn_baremetal/build/cnn_baremetal.elf`
- FSBL: `build/vitis_ws/arty_z7_20_cnn_platform/zynq_fsbl/build/fsbl.elf`
- Timing report: `build/arty_z7_20_bitstream_timing.rpt`
- Utilization report: `build/arty_z7_20_bitstream_util.rpt`

## Regenerate

```bash
make arty-z7-project
make arty-z7-bitstream
make arty-z7-xsa
make vitis-app
```

Or run the complete board implementation flow:

```bash
make full-arty-z7-flow
```
