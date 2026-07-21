# Zybo Z7-20 Board Implementation

This is the first full Vivado board implementation for the image-to-image CNN path. It integrates the AXI-Lite/AXI-Stream RTL top into a Zynq block design with PS7, AXI DMA, AXI interconnects, reset generation, and a 125 MHz PL clock.

The design is board-implementation-ready evidence. The bare-metal software now programs the register map, sends the packetized tensor job through AXI DMA, reads back the output stream, and checks it against the golden tensor data; see [baremetal_app.md](baremetal_app.md).

## Configuration

| Field | Value |
|---|---:|
| Project | `zybo_z7_20_cnn` |
| Board part | `digilentinc.com:zybo-z7-20:part0:1.2` |
| Part | `xc7z020clg400-1` |
| PS preset | Vendored official Digilent Zybo Z7-20 preset |
| PS reference clock | 33.333333 MHz |
| DDR | 1 GB DDR3L (`0x00000000`-`0x3FFFFFFF`) |
| UART | UART1 on MIO 48-49 at 115200 baud |
| SD / QSPI | SD0 on MIO 40-45; QSPI on MIO 1-6 |
| Board clock | 125.000 MHz |
| PL top | `cnn_image2image_system_bd_wrapper` |
| compute config | `PC=2`, `PK=4`, `MAX_CIN=16`, `MAX_COUT=16`, `MAX_PIXELS=16` |
| AXI-Lite base | `0x43C00000` |
| AXI DMA base | `0x40400000` |

## Timing

| Metric | Value |
|---|---:|
| WNS | 0.036 ns |
| TNS | 0.000 ns |
| WHS | 0.027 ns |
| THS | 0.000 ns |
| Timing met | True |

## Utilization

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 7,501 | 53,200 | 14.10% |
| Slice Registers | 7,673 | 106,400 | 7.21% |
| Block RAM Tile | 29 | 140 | 20.71% |
| DSPs | 4 | 220 | 1.82% |

## Artifacts

- Vivado project: `build/zybo_z7_20_cnn/zybo_z7_20_cnn.xpr`
- Bitstream: `build/zybo_z7_20_cnn/zybo_z7_20_cnn.runs/impl_1/system_wrapper.bit`
- XSA: `build/zybo_z7_20_cnn/zybo_z7_20_cnn.xsa`
- bare-metal ELF: `build/vitis_ws/cnn_baremetal/build/cnn_baremetal.elf`
- FSBL: `build/vitis_ws/zybo_z7_20_cnn_platform/zynq_fsbl/build/fsbl.elf`
- Timing report: `build/zybo_z7_20_bitstream_timing.rpt`
- Utilization report: `build/zybo_z7_20_bitstream_util.rpt`

## Regenerate

The board definition is vendored under `board_files/`, so no system-wide
Digilent board-file installation is required.

```bash
make zybo-z7-project
make zybo-z7-bitstream
make zybo-z7-xsa
make vitis-app
```

Or run the complete board implementation flow:

```bash
make full-zybo-z7-flow
```
