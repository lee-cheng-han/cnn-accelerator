set part_name xc7a35tcpg236-1
set top_name streaming_cnn_core

read_verilog -sv rtl/cnn_accel_pkg.sv
read_verilog -sv rtl/postprocess/bias_add.sv
read_verilog -sv rtl/postprocess/relu.sv
read_verilog -sv rtl/postprocess/quantizer.sv
read_verilog -sv rtl/postprocess/output_saturate.sv
read_verilog -sv rtl/compute/mac_unit.sv
read_verilog -sv rtl/compute/mac_array_3x3.sv
read_verilog -sv rtl/compute/adder_tree.sv
read_verilog -sv rtl/compute/channel_accumulator.sv
read_verilog -sv rtl/compute/conv_engine.sv
read_verilog -sv rtl/fpga/streaming_window_buffer.sv
read_verilog -sv rtl/fpga/streaming_cnn_core.sv

synth_design \
  -top $top_name \
  -part $part_name \
  -flatten_hierarchy none

create_clock -period 10.000 -name clk [get_ports clk]

file mkdir synth_out/streaming_cnn_core

report_utilization \
  -hierarchical \
  -file synth_out/streaming_cnn_core/utilization.rpt

report_timing_summary \
  -file synth_out/streaming_cnn_core/timing_summary.rpt

write_checkpoint \
  -force synth_out/streaming_cnn_core/streaming_cnn_core_synth.dcp

exit
