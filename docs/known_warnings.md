# Known Vivado Warnings

The project treats warnings as a budget, not background noise. Run:

```bash
make check-warnings
```

The check fails on any `ERROR`, any `CRITICAL WARNING`, or any warning outside the categories below.

## Current Policy

| Warning | Source | Why it is accepted |
|---|---|---|
| `Board 49-26` | Vivado board store scan | Local Vivado installation contains board files for parts not installed in this tool setup. This is environment noise before project creation. |
| `Boardtcl 53-1` | Vivado board metadata query | Board automation is queried while the project is targeting the Zynq part directly rather than an installed board preset. |
| `Project 1-5713` | Vivado project metadata | The design targets the Zynq part directly when board-part metadata is unavailable. |
| `BD 5-1069` | Optional System ILA monitor insertion | Vivado defaults monitor interface direction to input for the debug-only System ILA slots. The monitored AXI-Stream and AXI-Lite interfaces are passive taps. |
| `BD 41-2384` | Vivado block design | Generated AXI interconnect adapts one-bit DMA transaction IDs to the six-bit Zynq HP port ID field. Lower ID bits are sufficient for this single-master DMA design. |
| `IP_Flow 19-4994` | BD output products | Vivado overwrites generated IP constraint files when regenerating the block design. |
| `Vivado 12-7122` | Run management | Fresh builds do not have an incremental synthesis checkpoint. |
| `Synth 8-7071` | Generated IP wrappers | Optional DMA, reset, interconnect, or PS7 sideband ports are unused in this polling-based bare-metal design. |
| `Synth 8-7023` | Generated IP wrappers | Same root cause as `Synth 8-7071`; optional generated ports are intentionally omitted. |
| `Synth 8-689` | Generated AXI interconnect | Vivado-generated width adaptation between AXI-Lite/AXI memory interconnect wrappers. |
| `Synth 8-7129` | Generated AXI interconnect | Vivado trims generated clock/reset fanout or unused ID bits after block-design optimization. |
| `Power 33-332` | Power estimation | Vectorless power analysis warning about reset activity. Timing and functional closure do not depend on this estimate. |

## Warnings Already Cleaned

The AXI-Stream and AXI-Lite wrapper metadata has been annotated so Vivado no longer emits clock-association critical warnings for the custom CNN AXI block.

Resolved categories:

- `BD 41-967`: AXI-Stream interface not associated with a clock pin.
- `IP_Flow 19-3158`: missing `FREQ_HZ` bus-interface metadata.

## When To Tighten The Budget

After board validation, the next useful cleanup is to replace the generated interconnect warnings only if they block deeper verification or obscure real issues. Until then, the budget prioritizes zero functional warnings in handwritten RTL, zero critical warnings, timing closure, and reproducible board artifacts.
