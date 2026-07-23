# Runtime Model Metadata and Lifecycle

## Scope

`cnn_model_metadata_store` retains the V1 model header, layer descriptors,
tensor descriptors, and per-channel quantization descriptors in programmable
logic. It uses two complete metadata banks so software can stage a replacement
without modifying the active model.

The complete package and parameter payload remain in DDR. Phase 4 stores only
runtime metadata. Parameter transfer into reusable weight and post-processing
banks begins in Phase 6.

## Physical Organization

Each metadata bank contains:

| Record | Capacity | Words per record | Bytes per bank |
|---|---:|---:|---:|
| Model header | 1 | 32 | 128 |
| Layer descriptors | 8 | 32 | 1,024 |
| Tensor descriptors | 32 | 16 | 2,048 |
| Quantization descriptors | 32 | 48 | 6,144 |
| **Total** |  |  | **9,344** |

Two banks consume 18,688 metadata bytes before implementation overhead. The
payload stores use synchronous-read block RAM; contents are never reset or
copied. Ordered commit counters and bank-valid state determine which contents
may be consumed.

## Atomic Lifecycle

The staging state machine is:

```text
UNLOADED
  -> BEGIN_LOAD -> LOADING
  -> FINISH_LOAD -> LOADED_UNVALIDATED
  -> VALIDATE -> VALIDATED
  -> ACTIVATE -> UNLOADED
```

`active_valid` and `active_bank` are independent of the staging state. This
allows an active model to continue serving jobs while software fills the other
bank. Successful `ACTIVATE` changes `active_bank` in one clock cycle. It does
not copy descriptors.

The following safety rules are enforced:

- `BEGIN_LOAD` always selects the bank opposite `active_bank` and resets the
  staging transfer's ordered commit counters.
- Metadata writes and record commits are accepted only in `LOADING`.
- Failed validation leaves `active_bank`, `active_model_id`, and
  `active_generation_id` unchanged.
- Activation and active-model retirement are rejected while a job is busy.
- A failed replacement load never invalidates the previous active model.
- The Phase 5 descriptor-driven controller requires `active_valid` and reads
  only the atomically selected active metadata bank.

## Metadata Aperture

`METADATA_ADDRESS` encodes one 32-bit record word:

| Bits | Field |
|---:|---|
| `1:0` | kind: 0 header, 1 layer, 2 tensor, 3 quantization |
| `7:2` | record index |
| `13:8` | word index within the record |
| `31:14` | reserved, write zero |

Software writes `METADATA_ADDRESS`, writes `METADATA_DATA`, then commits the
record through `METADATA_COMMIT` only after every required word has been
written. Layer, tensor, and quantization records must be committed in ascending,
contiguous ID order beginning at zero. Out-of-order or malformed commits return
`BAD_DESCRIPTOR`.

`METADATA_DATA` reads the currently selected staging word. The underlying block
RAM has one clock of read latency, which is hidden by the address-register then
data-register AXI-Lite access sequence.

## Validation Boundary

Before touching hardware, software parses the complete package with
`parse_model_package()` and applies `validate_package_capabilities()`. That is
the canonical full validation path for package SHA-256, package and parameter
CRC32, table bounds, geometry, references, quantization, residual compatibility,
and target capabilities.

The Phase 4 RTL validator independently checks the metadata transfer itself:

- committed model header and all records declared by its counts
- V1 magic, descriptor versions, and descriptor sizes
- layer count 1-8, tensor count 2-32, and quantization count 1-32
- contiguous layer, tensor, and quantization IDs

Semantic descriptor execution checks now run beside the generalized runtime
controller. Parameter CRC verification is added when parameter banks become
runtime-loaded in Phase 6.

## Lifecycle Errors

| Value | Name | Meaning |
|---:|---|---|
| 0 | `OK` | no lifecycle failure |
| 1 | `BAD_STATE` | command or metadata operation is out of sequence |
| 2 | `BUSY` | activation or retirement attempted during a job |
| 3 | `BAD_ADDRESS` | metadata kind, record index, or word index is invalid |
| 4 | `INCOMPLETE` | a required record was not committed |
| 5 | `BAD_HEADER` | model magic or header version/size is invalid |
| 6 | `LIMIT` | model record count is outside the V1 capacity |
| 7 | `BAD_DESCRIPTOR` | descriptor version, size, or contiguous ID is invalid |

The error is sticky until software writes bit 0 of `MODEL_ERROR`, starts a new
load, or issues `CONTROL.clear`.

## Verification

`tb_model_metadata_store` proves bank isolation, complete activation, failed
replacement preservation, malformed-descriptor rejection, busy protection,
and retirement. `tb_axi_lite_slave` performs a complete one-layer metadata load
through the software-visible aperture and verifies active model readback.
