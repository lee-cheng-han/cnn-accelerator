# V2 Stream Interface Contract

This document defines the stream contract for the experimental v2 image-to-image CNN path. It describes the current simulation-facing interface on `stream_loaded_multi_layer_job_controller` and the intended mapping to a future AXI-facing wrapper.

The current v2 wrapper uses four logical ready/valid streams:

| Stream | Direction | Data width | Payload |
|---|---|---:|---|
| `activation_stream_*` | Host to accelerator | signed int8 | Input image tensor |
| `bias_stream_*` | Host to accelerator | signed int32 | Layer bias tensors |
| `weight_stream_*` | Host to accelerator | signed int8 | Layer weight tensors |
| `output_stream_*` | Accelerator to host | signed int8 | Final RGB output tensor |

All input streams use `valid`, `ready`, and `data`. The output stream uses `valid`, `ready`, `data`, and `last`.

## Global Job Configuration

Job configuration is supplied outside the tensor streams:

| Signal | Meaning |
|---|---|
| `image_width` | Input and output image width for the fixed same-size denoising network |
| `image_height` | Input and output image height for the fixed same-size denoising network |
| `final_residual_enable` | Enables final denoising reconstruction, `output = input - predicted_noise` |
| `start` | Starts one complete stream-load, compute, stream-store job |

For the current fixed network:

```text
layer 0: Conv 3x3,  3 -> 16, ReLU
layer 1: Conv 3x3, 16 -> 16, ReLU
layer 2: Conv 3x3, 16 ->  3
```

The current implementation assumes same-size output because all descriptors use stride 1 and padding 1.

## Transfer Ordering

After `start`, the producer must provide streams in this exact order:

```text
input activation tensor
layer 0 bias tensor
layer 0 weight tensor
layer 1 bias tensor
layer 1 weight tensor
layer 2 bias tensor
layer 2 weight tensor
```

The wrapper then runs the three-layer compute job and emits the output tensor.

The producer may apply backpressure by keeping `valid` low. The accelerator may apply backpressure by keeping `ready` low. A word transfers only when `valid && ready` is true on a rising clock edge. `data` must remain stable while `valid` is high and `ready` is low.

Input streams do not currently carry `last`; length is implied by `image_width`, `image_height`, and the fixed layer descriptors.

## Activation Stream

The activation stream contains only the three input RGB channels, not padded scratchpad channels.

| Field | Value |
|---|---|
| Words | `image_width * image_height * 3` |
| Data type | signed int8 |
| Order | pixel-major, channel-minor |

Word order:

```text
for pixel = 0 .. image_width*image_height-1:
  for channel = 0 .. 2:
    send input[pixel][channel]
```

Pixel index is row-major:

```text
pixel = y * image_width + x
```

Channel order is:

```text
0 = R
1 = G
2 = B
```

## Bias Stream

Biases are sent before the matching layer weights.

| Layer | Words | Data type | Order |
|---:|---:|---|---|
| 0 | 16 | signed int32 | output channel `0..15` |
| 1 | 16 | signed int32 | output channel `0..15` |
| 2 | 3 | signed int32 | output channel `0..2` |

Word order for each layer:

```text
for output_channel = 0 .. layer_output_channels-1:
  send bias[layer][output_channel]
```

## Weight Stream

Weights are sent after the matching layer biases.

| Layer | Shape | Words | Data type |
|---:|---|---:|---|
| 0 | `[16][3][3][3]` | `16 * 3 * 9` | signed int8 |
| 1 | `[16][16][3][3]` | `16 * 16 * 9` | signed int8 |
| 2 | `[3][16][3][3]` | `3 * 16 * 9` | signed int8 |

Weight order is output-channel major, input-channel minor, then kernel tap:

```text
for output_channel = 0 .. layer_output_channels-1:
  for input_channel = 0 .. layer_input_channels-1:
    for kernel_tap = 0 .. 8:
      send weight[layer][output_channel][input_channel][kernel_tap]
```

Kernel taps are row-major:

```text
tap 0  tap 1  tap 2
tap 3  tap 4  tap 5
tap 6  tap 7  tap 8
```

The current stream-loaded wrapper uses 3x3 weights for all three layers. The lower-level `weight_tensor_load_controller` can also represent 1x1 tensors, but that mode is not part of the fixed three-layer v2 wrapper contract yet.

## Output Stream

The output stream contains only the final three RGB channels.

| Field | Value |
|---|---|
| Words | `image_width * image_height * 3` |
| Data type | signed int8 |
| Order | pixel-major, channel-minor |
| `last` | Asserted with the final output word only |

Word order:

```text
for pixel = 0 .. image_width*image_height-1:
  for channel = 0 .. 2:
    receive output[pixel][channel]
```

`output_stream_last` must be high only for:

```text
pixel == image_width*image_height-1
channel == 2
```

## Future AXI Mapping

The current RTL exposes separate logical streams. A future AXI-facing wrapper can map them directly to independent AXI-stream channels:

| Logical signal | AXI-stream signal |
|---|---|
| `*_stream_valid` | `TVALID` |
| `*_stream_ready` | `TREADY` |
| `*_stream_data` | `TDATA` |
| `output_stream_last` | output `TLAST` |

For DMA systems with fewer physical streams, the preferred future packet format is a single input AXI stream with lightweight packet headers:

| Packet type | Payload |
|---:|---|
| `0` | Activation tensor |
| `1` | Layer 0 bias tensor |
| `2` | Layer 0 weight tensor |
| `3` | Layer 1 bias tensor |
| `4` | Layer 1 weight tensor |
| `5` | Layer 2 bias tensor |
| `6` | Layer 2 weight tensor |

Each packet should assert `TLAST` on its final payload word. The AXI wrapper should validate packet type, expected length, and packet order before releasing `start` into the core wrapper. This keeps the current compute controller simple while allowing a software/DMA path to use one memory-backed input stream.

## Error Handling Expectations

The AXI-facing wrapper should reject or flag:

- `image_width * image_height > MAX_PIXELS`
- Unsupported packet order
- Too few or too many words in any tensor packet
- Missing output `TREADY` timeout, if software chooses to enforce one
- A new `start` while a job is already busy

The current stream-loaded controller reports loader/store configuration errors through `error`, and reports completion through `done`.

## Verification Coverage

Current tests that enforce this contract:

| Test | Coverage |
|---|---|
| `tb_v2_tensor_load_controllers` | Activation and weight stream order, backpressure, and config errors |
| `tb_v2_ping_pong_buffers` | Concurrent load/compute bank use, bank handoff, data isolation, and illegal-request errors |
| `tb_v2_output_store_controller` | Output stream order, backpressure, `last`, zero-length, and config errors |
| `tb_v2_stream_loaded_multi_layer_job_controller` | Full stream-load, compute, stream-store identity network |
| `tb_v2_stream_loaded_full_network_golden_flow` | Generated Python tensors streamed through the full v2 wrapper and checked bit-for-bit |

Run:

```bash
make v2-golden-test
make v2-unit
```
