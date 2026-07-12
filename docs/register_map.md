# AXI-Lite Register Map

`cnn_axi_lite_slave` provides the software control plane for
`cnn_image2image_system_top`. Tensor payloads remain on AXI-Stream; AXI-Lite is
used for job configuration, commands, status, interrupts, diagnostics, and
performance snapshots.

All registers are 32 bits wide and word-aligned. Writable registers honor
`WSTRB`. Writes to read-only or unmapped addresses return `SLVERR`; unmapped
reads return `0xDEAD_BEEF` with `SLVERR`.

| Offset | Name | Access | Description |
|---:|---|---|---|
| `0x000` | `CONTROL` | WO | Bit 0: start pulse; bit 1: clear pulse |
| `0x004` | `STATUS` | RO | Live job and scheduler state |
| `0x008` | `IRQ_STATUS` | RW1C | Bit 0: job done; bit 1: job error |
| `0x00C` | `IRQ_ENABLE` | RW | Enables corresponding `IRQ_STATUS` bits |
| `0x010` | `IMAGE_WIDTH` | RW | Image width in pixels |
| `0x014` | `IMAGE_HEIGHT` | RW | Image height in pixels |
| `0x018` | `MODE_FLAGS` | RW | Bit 0: final residual subtraction enable |
| `0x01C` | `ERROR_CODE` | RO | Packet-router or compute error code |
| `0x020` | `STREAM_STATE` | RO | Bits 2:0 packet type; bits 5:3 ready layers |
| `0x024` | `PACKET_WORDS` | RO | Payload words accepted in current packet |
| `0x080` | `PERF_JOB_CYCLES` | RO | Total active job cycles |
| `0x084` | `PERF_PACKET_CYCLES` | RO | Packet-router active cycles |
| `0x088` | `PERF_COMPUTE_CYCLES` | RO | Scheduler compute-active cycles |
| `0x08C` | `PERF_PREFETCH_CYCLES` | RO | Parameter prefetch overlap cycles |
| `0x090` | `PERF_LAYER0_CYCLES` | RO | Layer 0 selected compute cycles |
| `0x094` | `PERF_LAYER1_CYCLES` | RO | Layer 1 selected compute cycles |
| `0x098` | `PERF_LAYER2_CYCLES` | RO | Layer 2 selected compute cycles |
| `0x09C` | `PERF_INPUT_WORDS` | RO | Accepted input AXI-Stream words |
| `0x0A0` | `PERF_INPUT_STALLS` | RO | Input valid without ready cycles |
| `0x0A4` | `PERF_OUTPUT_WORDS` | RO | Accepted output AXI-Stream words |
| `0x0A8` | `PERF_OUTPUT_STALLS` | RO | Output valid without ready cycles |
| `0x0FC` | `VERSION` | RO | Register-map version, currently `0x00020000` |

## Status Bits

| Bits | Meaning |
|---:|---|
| `0` | Busy |
| `1` | Done |
| `2` | Error |
| `3` | Performance counters active |
| `7:4` | Scheduler phase |
| `9:8` | Active layer |
| `12:10` | Layer parameter-ready mask |
| `13` | Parameter prefetch active |
| `14` | Parameter prefetch observed during this job |

## Command Sequence

Software should configure the image before issuing start:

```text
write IMAGE_WIDTH
write IMAGE_HEIGHT
write MODE_FLAGS
write IRQ_STATUS = 0x3
write IRQ_ENABLE
write CONTROL = 0x1
stream the seven input packets
wait for IRQ or poll STATUS
read ERROR_CODE and performance registers
```

`CONTROL.clear` resets the active packet/compute job and clears pending interrupt
status. Completion and error interrupts are edge-captured and remain pending
until cleared through `IRQ_STATUS` or `CONTROL.clear`.

The current wrapper shares one clock/reset domain between AXI-Lite, AXI-Stream,
and the accelerator. A future block design must insert clock converters if those
interfaces use different clocks.
