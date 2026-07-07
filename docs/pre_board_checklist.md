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
| Warning budget | Done | `make check-warnings`, `docs/known_warnings.md` |
| Automated flow summary | Done | `make flow-report`, writes `build/flow_report.md`; latest docs snapshot in `docs/logs/pre_board_flow_report.md` |
| SD boot image packaging | Done | `make boot-image`, writes `build/BOOT.BIN` |
| Board arrival runbook | Done | `docs/board_arrival_runbook.md` |
| AXI protocol assertions | Done | AXI-Stream stable-data/TLAST checks and AXI-Lite channel hold checks |
| More randomized DMA top tests | Done | deterministic randomized output backpressure in 3x3 and 1x1 DMA tests |
| Coverage-style summary | Done | `docs/verification_matrix.md`, `docs/logs/dma_top_sim_pass.log`, and `build/flow_report.md` |
| Fresh XSim logs | Done | `make dma-sim` passes with AXI assertions and output backpressure |

## Board Arrival Checklist

1. Connect Arty Z7-20 over USB.
2. Set boot mode to JTAG.
3. Open UART terminal at 115200 baud, 8N1, no flow control.
4. Run `make program-arty-z7-dma`.
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
CNN status
CNN result stat
CNN status decode
CNN result decode
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
