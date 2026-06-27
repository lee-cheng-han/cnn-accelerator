# Verification Plan

## Verification Scope

The design is verified at multiple levels:

1. Individual RTL module testing
2. AXI-Lite register interface testing
3. Integrated AXI system testing
4. Vivado synthesis and implementation checks
5. Bare-metal ARM software build validation
6. Planned board-level hardware test on Arty Z7-20

## Verification Goals

| Area | Goal |
|---|---|
| RTL correctness | Validate datapath and control behavior |
| AXI-Lite protocol | Verify register reads/writes and response behavior |
| Configuration loading | Verify weights, biases, image size, and mode flags |
| Streaming input | Verify pixel input path |
| Result readback | Verify result buffer read behavior |
| Zynq integration | Verify PS to PL AXI connectivity |
| Build reproducibility | Verify complete flow from scripts |
| Timing | Ensure implemented design meets timing |

## RTL Verification

Expected RTL test coverage includes:

- reset behavior
- control register writes
- status register reads
- image width/height configuration
- weight register loading
- bias register loading
- pixel input writes
- result buffer reads
- ReLU enable/disable behavior
- quantization mode behavior
- random and directed datapath cases

## AXI-Lite Verification

AXI-Lite testbenches check:

- write address/data handshake
- write response behavior
- read address handshake
- read data response
- register write/read correctness
- control pulse behavior
- invalid or unused address behavior
- status/result register behavior

## System-Level Verification

The integrated AXI system test verifies that the AXI-Lite slave, configuration registers, streaming input path, CNN datapath, and result readback path operate together.

## Build Verification

Hardware/software build flow:

```bash
make arty-z7-project
make arty-z7-bitstream
make arty-z7-xsa
make vitis-app
```

Full flow:

```bash
make full-arty-z7-flow
```

Passing criteria:

- Vivado project is generated
- block design is valid
- bitstream is generated
- timing is met
- XSA is exported
- Vitis bare-metal ELF is generated

## Current Status

| Verification Item | Status |
|---|---|
| RTL simulation | Passing |
| AXI-Lite testbench | Passing |
| AXI system testbench | Passing |
| Synthesis | Passing |
| Implementation | Passing |
| Timing | Met |
| XSA export | Passing |
| Vitis app build | Passing |
| Board execution | Next step |

## Board-Level Test Plan

The board-level test will run the generated ELF on the Zynq ARM processor after programming the FPGA bitstream.

Expected sequence:

1. Program FPGA with `system_wrapper.bit`
2. Run `cnn_baremetal.elf` on ARM Cortex-A9
3. Open UART terminal
4. Confirm startup banner
5. Confirm accelerator status reads
6. Confirm result words are printed
7. Compare output values against expected software-side behavior

Expected UART banner:

```text
Zynq CNN Accelerator Bare-Metal Test
```
