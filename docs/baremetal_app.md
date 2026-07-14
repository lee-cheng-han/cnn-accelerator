# Bare-Metal Golden DMA App

The bare-metal app drives the packetized image-to-image accelerator through the Zybo Z7-20 AXI DMA block design.

It uses the deterministic Python golden tensor case from `build/golden/full_network_3layer`, converts it into the seven-packet AXI input stream, runs both residual and non-residual output modes, and compares the returned DMA output buffer against the expected signed INT8 RGB pixels.

## Software Flow

The app performs the following sequence for each test mode:

1. Reset AXI DMA.
2. Clear the accelerator.
3. Program `IMAGE_WIDTH`, `IMAGE_HEIGHT`, and `MODE_FLAGS`.
4. Clear pending interrupt status.
5. Start S2MM and MM2S DMA channels.
6. Pulse `CONTROL.start`.
7. Launch S2MM length before MM2S length.
8. Poll DMA completion and `STATUS.done`.
9. Print diagnostics and performance counters.
10. Compare all returned output words against the generated golden data.

Expected final UART result:

```text
[PASS] image-to-image DMA golden test passed
```

## Artifacts

- App source: `software/zynq_baremetal/main.c`
- Generated golden C header: `software/zynq_baremetal/generated/golden_dma_job.h`
- Vitis app generator: `scripts/vitis/create_zynq_baremetal_app.py`
- Built ELF: `build/vitis_ws/cnn_baremetal/build/cnn_baremetal.elf`
- Generated FSBL: `build/vitis_ws/zybo_z7_20_cnn_platform/zynq_fsbl/build/fsbl.elf`
- Hardware platform: `build/zybo_z7_20_cnn/zybo_z7_20_cnn.xsa`

## Regenerate

```bash
make vitis-app
```

The target regenerates the Python golden tensors, emits the C packet/expected-output header, creates the Vitis platform from the XSA, and builds `cnn_baremetal.elf`.
