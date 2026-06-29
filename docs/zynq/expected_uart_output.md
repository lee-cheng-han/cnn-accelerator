# Expected UART Output

This file documents the expected output for the initial bare-metal CNN accelerator test.

## Test Configuration

| Item | Value |
|---|---|
| Input image | 4x4 RGB |
| Input channels | 3 |
| Output channels | 4 |
| Kernel | 3x3 |
| Bias | Zero |
| ReLU | Enabled |
| Quantization | Disabled |

## Weight Configuration

The test uses center-tap identity-like weights.

| Output Channel | Function |
|---|---|
| `oc0` | R center pixel |
| `oc1` | G center pixel |
| `oc2` | B center pixel |
| `oc3` | R + G + B center pixel |

## Expected Result Words

For a 4x4 image with valid 3x3 windows, there are 2x2 output positions. With 4 output channels, the expected output count is 16 words.

```text
expected[00] = 2
expected[01] = 2
expected[02] = 3
expected[03] = 7
expected[04] = 3
expected[05] = 2
expected[06] = 4
expected[07] = 9
expected[08] = 2
expected[09] = 3
expected[10] = 4
expected[11] = 9
expected[12] = 3
expected[13] = 3
expected[14] = 5
expected[15] = 11