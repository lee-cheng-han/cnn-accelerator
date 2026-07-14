# Board Arrival Runbook

Use this when the Zybo Z7-20 arrives. The goal is to capture enough evidence that the project moves from pre-board complete to hardware validated.

## Before Plugging In

Run the pre-board proof flow:

```bash
make preboard-proof
```

Expected outputs:

```text
build/zybo_z7_20_cnn/zybo_z7_20_cnn.runs/impl_1/system_wrapper.bit
build/zybo_z7_20_cnn/zybo_z7_20_cnn.xsa
build/vitis_ws/cnn_baremetal/build/cnn_baremetal.elf
build/BOOT.BIN
build/flow_report.md
```

## First Run Over JTAG

1. Set the Zybo Z7-20 boot jumper to JTAG.
2. Connect USB power/programming.
3. Open UART at 115200 baud, 8N1, no flow control.
4. Run:

```bash
make program-zybo-z7
```

Expected final line:

```text
[PASS] image-to-image DMA golden test passed
```

Save the UART transcript to:

```text
docs/logs/board_dma_pass.log
```

Also record these timing lines from the same run:

```text
DMA+ transfer cycles = <measured>
DMA+ transfer usec = <measured>
 perf job cycles = <measured>
 perf compute cycles = <measured>
```

## Optional SD Boot Check

After JTAG passes:

1. Copy `build/BOOT.BIN` to a FAT32 microSD card.
2. Set boot mode to SD.
3. Power cycle the board.
4. Capture the same UART PASS transcript.

## Optional ILA Debug Build

If UART shows a DMA timeout, TLAST mismatch, or unexpected output count, add an ILA/debug block-design variant and trigger on:

```text
SLOT_0_AXIS TVALID && TREADY: DMA MM2S pixel accepted by CNN
SLOT_0_AXIS TLAST: final input pixel
SLOT_1_AXIS TVALID && TREADY: CNN output accepted by DMA S2MM
SLOT_1_AXIS TLAST: final output word
SLOT_2_AXI AW/W/B channels: CNN register writes
```

Use any ILA bitstream for debug only, then switch back to the clean bitstream for final timing/performance evidence.

## Evidence To Add To The Repo

| Evidence | Destination |
|---|---|
| UART PASS log | `docs/logs/board_dma_pass.log` |
| Flow summary generated on validation day | `docs/logs/board_flow_report.md` |
| Setup photo or screenshot | `docs/assets/board_setup.*` |
| Any first-failure notes | `docs/BOARD_BRINGUP.md` |
| Measured latency/throughput | `docs/performance_results.md` |

## Debug If First Run Fails

Capture these UART lines before changing RTL:

```text
DMA MM2S after reset status
DMA MM2S after reset status decode
DMA S2MM after reset status
DMA S2MM after reset status decode
Input buffer address
Output buffer address
Input bytes
Output bytes
DMA MM2S final status
DMA MM2S final status decode
DMA S2MM final status
DMA S2MM final status decode
 status
 irq_status
 error_code
 stream_state
 packet_words
 perf counters
[FAIL] lines
```

Most likely first issues are UART device selection, boot jumper mode, stale bitstream/ELF pair, cache maintenance around DMA buffers, packet length/order errors, or a DMA byte-count/TLAST mismatch.
