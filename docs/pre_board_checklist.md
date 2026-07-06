# Pre-Board Checklist

This checklist captures work that can be completed before the Arty Z7-20 arrives.

## Already Complete

- DMA top-level RTL exists.
- AXI-Lite register interface exists.
- AXI DMA Vivado block design script exists.
- Generated image/golden header flow exists.
- Bare-metal DMA validation application exists.
- Full DMA top-level XSim test passes in checked-in proof log.
- Bitstream, XSA, and ELF have been built locally according to checked-in artifact logs.
- Board bring-up command and UART expectations are documented.

## High-Impact Pre-Board Polish

| Item | Status | Notes |
|---|---|---|
| README results snapshot | Done | top-level portfolio summary |
| Current-vs-legacy path explanation | Done | README and block diagram docs |
| Case study | Done | `docs/case_study.md` |
| Verification matrix | Done | `docs/verification_matrix.md` |
| Performance analysis | Done | `docs/performance_analysis.md` |
| Board bring-up checklist | Done | `docs/BOARD_BRINGUP.md` |
| AXI-Stream assertions | Todo | stable data while stalled, TLAST checks |
| More randomized DMA top tests | Todo | include output backpressure |
| Coverage-style summary | Todo | modes, shapes, post-processing, stalls |
| Fresh XSim logs | Todo | rerun after local XSim launch-wrapper issue is resolved |

## Board Arrival Checklist

1. Connect Arty Z7-20 over USB.
2. Set boot mode to JTAG.
3. Open UART terminal at 115200 baud, 8N1, no flow control.
4. Run `make program-arty-z7-dma`.
5. Capture UART output.
6. Save a passing log under `docs/logs/board_dma_pass.log`.
7. Add a setup photo under a docs asset directory.
8. Update README board status from pending to passing.

## Debug Data To Capture If Bring-Up Fails

Paste or save these UART lines:

```text
DMA MM2S status after reset
DMA S2MM status after reset
Input buffer address
Output buffer address
Input bytes
Output bytes
DMA MM2S final status
DMA S2MM final status
CNN status
CNN result stat
[FAIL] lines
```

## Likely First-Failure Areas

- UART terminal on the wrong serial device or baud rate.
- Boot mode not set to JTAG.
- DMA output byte count not matching the number of produced output words.
- Cache flush/invalidate issue around DDR buffers.
- AXI DMA error bit set after transfer.
- TLAST mismatch between produced stream and S2MM expected length.

## Definition Of Done For Board Validation

Board validation is complete when the repo includes:

- UART log showing `[PASS] CNN DMA accelerator test passed`.
- Date and tool version used for the run.
- Bitstream and ELF path used.
- Board setup photo.
- Any bring-up issue notes and their fix.
