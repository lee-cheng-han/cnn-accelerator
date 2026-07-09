# V2 Performance Counters

`v2_performance_counters` records one snapshot for each accepted v2 AXI job. Counting starts when the packet router accepts `start` and stops when the compute job completes or a protocol/core error aborts it.

All counters are unsigned 32-bit wrapping counters. They clear on reset, `clear`, or the next accepted job and retain their final values after counting stops.

## Counter Definitions

| Counter | Increment condition |
|---|---|
| `perf_job_cycles` | Every cycle while the accepted job is active |
| `perf_packet_cycles` | Packet router is receiving a header or payload |
| `perf_compute_cycles` | Multi-layer scheduler is active |
| `perf_prefetch_cycles` | Later-layer parameter loading overlaps scheduler activity |
| `perf_layer0_cycles` | Scheduler active with layer 0 selected |
| `perf_layer1_cycles` | Scheduler active with layer 1 selected |
| `perf_layer2_cycles` | Scheduler active with layer 2 selected |
| `perf_input_words` | Input `TVALID && TREADY`, including seven headers |
| `perf_input_stall_cycles` | Input `TVALID && !TREADY` |
| `perf_output_words` | Output `TVALID && TREADY` |
| `perf_output_stall_cycles` | Output `TVALID && !TREADY` |

`perf_counting` indicates that the counters currently belong to an active job.

The layer counters include scheduler transition and readiness-wait cycles because the multi-layer scheduler still owns the selected layer during those intervals. Therefore:

```text
perf_compute_cycles
  = perf_layer0_cycles
  + perf_layer1_cycles
  + perf_layer2_cycles
```

For the fixed default network, a complete input contains:

```text
7 packet headers
+ width * height * 3 activation words
+ 16 + (16 * 3 * 9) layer 0 parameter words
+ 16 + (16 * 16 * 9) layer 1 parameter words
+ 3  + (3 * 16 * 9) layer 2 parameter words
```

The counters are direct top-level outputs today. The planned v2 AXI-Lite control block will expose the same snapshot through read-only registers.
