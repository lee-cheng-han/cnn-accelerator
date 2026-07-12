# V2 Bare-Metal Golden DMA App

The v2 bare-metal app drives the packetized image-to-image accelerator through the Arty Z7-20 AXI DMA block design.

It uses the deterministic Python golden tensor case from `build/v2_golden/full_network_3layer`, converts it into the seven-packet AXI input stream, runs both residual and non-residual output modes, and compares the returned DMA output buffer against the expected signed INT8 RGB pixels.

## Software Flow

The app performs the following sequence for each test mode:

1. Reset AXI DMA.
2. Clear the v2 accelerator.
3. Program `IMAGE_WIDTH`, `IMAGE_HEIGHT`, and `MODE_FLAGS`.
4. Clear pending v2 interrupt status.
5. Start S2MM and MM2S DMA channels.
6. Pulse v2 `CONTROL.start`.
7. Launch S2MM length before MM2S length.
8. Poll DMA completion and v2 `STATUS.done`.
9. Print v2 diagnostics and performance counters.
10. Compare all returned output words against the generated golden data.

Expected final UART result:

```text
[PASS] V2 image-to-image DMA golden test passed
```

## Artifacts

- App source: `software/zynq_v2_baremetal/main.c`
- Generated golden C header: `software/zynq_v2_baremetal/generated/v2_golden_dma_job.h`
- Vitis app generator: `scripts/vitis/create_zynq_v2_baremetal_app.py`
- Built ELF: `build/vitis_ws_v2/cnn_v2_baremetal/build/cnn_v2_baremetal.elf`
- Generated FSBL: `build/vitis_ws_v2/arty_z7_20_cnn_v2_platform/zynq_fsbl/build/fsbl.elf`
- Hardware platform: `build/arty_z7_20_cnn_v2/arty_z7_20_cnn_v2.xsa`

## Regenerate

```bash
make vitis-v2-app
```

The target regenerates the Python golden tensors, emits the C packet/expected-output header, creates the Vitis platform from the v2 XSA, and builds `cnn_v2_baremetal.elf`.
