# Activation Buffer Utilization Issue

Vivado hierarchical utilization shows that most LUT usage comes from the activation buffer:

- activation_buffer LUTs: 59,076
- activation_buffer FFs: 24,576
- activation_buffer BRAM: 0

Root cause:
The current activation_buffer stores the full image and exposes 27 simultaneous asynchronous reads:
3 input channels x 9 kernel taps = 27 read ports.

Vivado cannot infer BRAM for this structure, so it maps the storage/read muxing into LUTs and registers.

Board-ready fix:
Replace the full-image asynchronous-read buffer with a streaming line-buffer/window-generator architecture.
