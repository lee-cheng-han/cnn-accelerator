set part_name xc7a35tcpg236-1
set top_name cnn_accel_board_top

read_verilog -sv rtl/fpga/uart_rx.sv
read_verilog -sv rtl/fpga/uart_tx.sv
read_verilog -sv rtl/fpga/cnn_accel_board_top.sv

synth_design \
  -top $top_name \
  -part $part_name \
  -flatten_hierarchy none

create_clock -period 10.000 -name clk [get_ports clk]

file mkdir synth_out/board_top

report_utilization \
  -hierarchical \
  -file synth_out/board_top/utilization.rpt


report_utilization \
  -file synth_out/board_top/utilization_full.rpt

report_io \
  -file synth_out/board_top/io.rpt

report_timing_summary \
  -file synth_out/board_top/timing_summary.rpt

write_checkpoint \
  -force synth_out/board_top/cnn_accel_board_top_synth.dcp

exit
