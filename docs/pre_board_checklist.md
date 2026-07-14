# Pre-Board Checklist

This checklist captures work that can be completed before the Zybo Z7-20 arrives.

## Already Complete

- image-to-image top-level RTL exists.
- AXI-Lite register interface exists.
- AXI DMA Vivado block design script exists.
- generated golden tensor and C DMA packet header flow exists.
- bare-metal DMA validation application exists.
- full-network AXI packet golden RTL tests pass.
- bitstream, XSA, FSBL, and ELF have been built locally.
- board bring-up command and UART expectations are documented.

## High-Impact Pre-Board Polish

| Item | Status | Notes |
|---|---|---|
| README results snapshot | Done | top-level portfolio summary |
| architecture explanation | Done | README, architecture, and block diagram docs |
| Case study | Done | `docs/case_study.md` |
| Verification matrix | Done | `docs/verification_matrix.md` |
| Performance analysis | Done | `docs/performance_results.md` |
| Board bring-up checklist | Done | `docs/BOARD_BRINGUP.md` |
| Warning budget | Done | `make check-warnings`, `docs/known_warnings.md` |
| Automated flow summary | Done | `make flow-report`, writes `build/flow_report.md`; latest docs snapshot in `docs/logs/pre_board_flow_report.md` |
| SD boot image packaging | Done | `make boot-image`, writes `build/BOOT.BIN` |
| Board arrival runbook | Done | `docs/board_arrival_runbook.md` |
| AXI protocol checks | Done | packetized AXI-stream tests cover ordering, lengths, TLAST, malformed jobs, and backpressure |
| Coverage-style summary | Done | `docs/verification_matrix.md` and `build/flow_report.md` |
| Fresh XSim logs | Done | `make regression` passes the model, golden, and RTL unit flow |

## Board Arrival Checklist

1. Connect Zybo Z7-20 over USB.
2. Set boot mode to JTAG.
3. Open UART terminal at 115200 baud, 8N1, no flow control.
4. Run `make program-zybo-z7`.
5. Capture UART output.
6. Save a passing log under `docs/logs/board_dma_pass.log`.
7. Add a setup photo under a docs asset directory.
8. Update README board status from pending to passing.
9. Copy `build/flow_report.md` to `docs/logs/board_flow_report.md`.

## Debug Data To Capture If Bring-Up Fails

Paste or save these UART lines:

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

## Likely First-Failure Areas

- UART terminal on the wrong serial device or baud rate.
- Boot mode not set to JTAG.
- DMA output byte count not matching the number of produced output words.
- Cache flush/invalidate issue around DDR buffers.
- AXI DMA error bit set after transfer.
- TLAST mismatch between produced stream and S2MM expected length.
- packet header, order, or payload length mismatch.

## Definition Of Done For Board Validation

Board validation is complete when the repo includes:

- UART log showing `[PASS] image-to-image DMA golden test passed`.
- Date and tool version used for the run.
- Bitstream and ELF path used.
- Board setup photo.
- Any bring-up issue notes and their fix.
