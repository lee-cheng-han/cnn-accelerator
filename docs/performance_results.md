# Performance Results

The design exposes these counters:

- `cycle_count`
- `input_pixel_count`
- `window_count`
- `mac_count`
- `output_count`
- `stall_count`
- `fifo_full_count`

For the default 3 input channels, 4 output channels, and 3x3 kernel:

```text
MAC-equivalent operations per output pixel = 3 x 4 x 9 = 108
```

For an H x W image with valid convolution:

```text
output pixels per output channel = (H - 2) x (W - 2)
total output values = 4 x (H - 2) x (W - 2)
total MAC-equivalent operations = 108 x (H - 2) x (W - 2)
```
