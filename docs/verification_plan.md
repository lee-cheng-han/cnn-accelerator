# Verification Plan

## Verification Scope

The design is verified at multiple levels:

1. Python bit-accurate model tests
2. RTL unit tests
3. Full-network golden tensor RTL tests
4. Packetized AXI-stream system tests
5. AXI-Lite register and performance-counter tests
6. Vivado synthesis and implementation checks
7. Vitis bare-metal app build validation
8. Planned board-level hardware test on Arty Z7-20

## Verification Goals

| Area | Goal |
|---|---|
| Model correctness | Validate signed INT8/INT32 image-to-image arithmetic |
| RTL correctness | Validate compute, scratchpad, scheduler, and stream behavior |
| Packet protocol | Verify packet order, length, headers, TLAST, and error reporting |
| AXI-Lite protocol | Verify register reads/writes, command pulses, status, and counters |
| Zynq integration | Verify PS, AXI DMA, AXI-Lite, AXI-Stream, reset, and clock connectivity |
| Build reproducibility | Verify complete scripted flow from RTL to XSA/ELF/BOOT.BIN |
| Timing | Ensure implemented design meets 125 MHz |

## RTL Verification

Expected RTL coverage includes:

- reset and clear behavior
- tensor address generation
- tail masks for non-divisible channel tiles
- tiled 1x1 and 3x3 compute engines
- banked activation and weight scratchpad reads
- activation, bias, and weight load streams
- output stream ordering and `last`
- multi-layer scheduler sequencing
- parameter prefetch overlap
- residual and non-residual output modes
- packet router malformed-input errors
- output backpressure
- performance counter snapshots

## Build Verification

Primary hardware/software build flow:

```bash
make full-preboard-proof
```

Equivalent important substeps:

```bash
make regression
make full-arty-z7-flow
make boot-image
make flow-report
```

Passing criteria:

- Python model tests pass
- golden RTL tests pass
- unit RTL tests pass
- Vivado project is generated
- block design is valid
- bitstream is generated
- timing is met at 125 MHz
- XSA is exported
- Vitis bare-metal ELF is generated
- `build/BOOT.BIN` is packaged

## Current Status

| Verification Item | Status |
|---|---|
| Python model tests | Passing |
| golden RTL tests | Passing |
| unit RTL tests | Passing |
| Zynq block design | Passing |
| implementation | Passing |
| Timing | Met at 125 MHz |
| XSA export | Passing |
| Vitis app build | Passing |
| BOOT.BIN | Passing |
| Board execution | Pending hardware |

## Board-Level Test Plan

The board-level test will run the generated ELF on the Zynq ARM processor after programming the FPGA bitstream.

Expected sequence:

1. Program FPGA with the `system_wrapper.bit`.
2. Run `cnn_baremetal.elf` on ARM Cortex-A9.
3. Open UART terminal.
4. Confirm startup banner.
5. Confirm register version.
6. Confirm residual and non-residual golden DMA jobs pass.
7. Archive printed performance counters.

Expected UART banner:

```text
Zynq Image-to-Image CNN DMA Test
```

Expected final line:

```text
[PASS] image-to-image DMA golden test passed
```
