# Block Diagram

```text
                 +-------------------+
 cfg interface -> | config_regs       |
                 +---------+---------+
                           |
                           v
 AXIS input ---> axis_input_if ---> activation_buffer
                           |              |
                           |              v
                           |        window addresses
                           |              |
                           v              v
                    accel_controller -> output_channel_array
                                         |  |  |  |
                                         v  v  v  v
                                   conv_engine per output channel
                                         |
                              bias -> ReLU -> quantize -> saturate
                                         |
 AXIS output <--- axis_output_if <-------+

 perf_counters observe input/output/windows/stalls
```
