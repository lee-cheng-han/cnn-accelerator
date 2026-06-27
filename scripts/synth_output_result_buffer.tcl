set part_name xc7a35tcpg236-1
set top_name output_result_buffer

read_verilog -sv rtl/fpga/output_result_buffer.sv

synth_design \
  -top $top_name \
  -part $part_name \
  -generic DATA_WIDTH=8 \
  -generic DEPTH=16384 \
  -flatten_hierarchy none

create_clock -period 10.000 -name clk [get_ports clk]

file mkdir synth_out/output_result_buffer

report_utilization \
  -hierarchical \
  -file synth_out/output_result_buffer/utilization.rpt

report_utilization \
  -file synth_out/output_result_buffer/utilization_full.rpt

report_timing_summary \
  -file synth_out/output_result_buffer/timing_summary.rpt

write_checkpoint \
  -force synth_out/output_result_buffer/output_result_buffer_synth.dcp

exit
