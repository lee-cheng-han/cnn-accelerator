set part_name xc7a35tcpg236-1
set top_name streaming_window_buffer

read_verilog -sv rtl/fpga/streaming_window_buffer.sv

synth_design \
  -top $top_name \
  -part $part_name \
  -flatten_hierarchy none

create_clock -period 10.000 -name clk [get_ports clk]

file mkdir synth_out/streaming_window_buffer

report_utilization \
  -hierarchical \
  -file synth_out/streaming_window_buffer/utilization.rpt

report_timing_summary \
  -file synth_out/streaming_window_buffer/timing_summary.rpt

write_checkpoint \
  -force synth_out/streaming_window_buffer/streaming_window_buffer_synth.dcp

exit
