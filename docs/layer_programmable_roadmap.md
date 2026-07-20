# Layer-Programmable Accelerator Roadmap

## Objective

The final system is a versioned, layer-programmable INT8 image accelerator on a
single 125 MHz Zybo Z7-20 bitstream. It executes fixed image-processing kernels
such as blur and edge detection as well as compatible learned image-to-image
CNNs. Models are compiled into relocatable packages, staged and validated,
atomically activated, and reused across multiple images.

## Milestones

| Phase | Deliverable | Status |
|---:|---|---|
| 0 | Preserve fixed-network board baseline and evidence | Complete; physical board validation pending |
| 1 | Freeze exact V1 model-package ABI | Complete |
| 2 | Build model compiler and package-level bit-accurate executor | Next |
| 3 | Add capability discovery and structured errors | Planned |
| 4 | Add runtime metadata memories and atomic model lifecycle | Planned |
| 5 | Generalize descriptor-driven layer execution control | Planned |
| 6 | Add reusable active/prefetch parameter banks | Planned |
| 7 | Introduce packed, versioned DMA protocol | Planned |
| 8 | Implement DDR-backed spatial tiling and halo handling | Planned |
| 9 | Complete residual and quantization behavior in runtime RTL | Planned |
| 10 | Build runtime software and connect interrupts | Planned |
| 11 | Add autonomous DDR fetching | Planned |
| 12 | Expand protocol, randomized, golden, and negative verification | Planned |
| 13 | Optimize performance and validate physical hardware | Planned |

Phase 5 accepts descriptor-driven sequencing through a temporary or
software-reloaded parameter path. Phase 6 is the point at which networks of one
to eight mixed layers execute through reusable active and prefetch parameter
banks. The packed DMA protocol precedes full tiling because tile transfers
depend on tensor IDs, coordinates, byte counts, partial beats, and recovery
semantics.

## Final Workflow

```text
network.yaml + signed INT8 weights
  -> Python model compiler
  -> relocatable V1 package in DDR
  -> load staging metadata
  -> validate checksums, capabilities, and references
  -> atomically activate model generation
  -> run multiple input images
  -> output tensors and per-layer performance records
```

The complete model package remains in DDR. Descriptors and tensor/quantization
metadata are retained in accelerator memory. Layer parameters are prefetched
from DDR into reusable banks as needed. A final `RUN_IMAGE` launches a complete
job without CPU intervention for every tile or layer.

## Performance Framing

At eight issued MACs per cycle and 125 MHz, arithmetic peak is approximately
1 GMAC/s. An eight-layer 16-to-16-channel 3x3 network at 1024x1024 contains
approximately 19.3 billion MACs, so its ideal compute lower bound is roughly
19.3 seconds before transfer and control overhead. Accordingly:

- 224x224 is the primary recognizable CNN benchmark.
- 512x512 is the substantial image-processing demonstration.
- 1024x1024 is the functional maximum and stress test.

Claims about real-time operation will be based on post-route and physical-board
measurements, not the dimensional capability limit.
