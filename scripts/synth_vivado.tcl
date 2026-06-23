# scripts/synth_vivado.tcl

set_param general.maxThreads 8

file mkdir synth_out

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
read_verilog -sv rtl/compute/output_channel_array.sv

read_verilog -sv rtl/control/config_regs.sv
read_verilog -sv rtl/control/accel_controller.sv
read_verilog -sv rtl/control/perf_counters.sv

read_verilog -sv rtl/stream/stream_fifo.sv
read_verilog -sv rtl/stream/axis_input_if.sv
read_verilog -sv rtl/stream/axis_output_if.sv

read_verilog -sv rtl/buffer/activation_buffer.sv
read_verilog -sv rtl/buffer/weight_buffer.sv
read_verilog -sv rtl/buffer/line_buffer_3x3.sv
read_verilog -sv rtl/buffer/window_generator_3x3.sv

read_verilog -sv rtl/cnn_accel_top.sv

synth_design -top cnn_accel_top -part xc7a35tcpg236-1

read_xdc constraints/cnn_accel_top.xdc

report_clocks -file synth_out/clocks.rpt
report_timing_summary -file synth_out/timing_summary.rpt
report_utilization -file synth_out/utilization.rpt
report_drc -file synth_out/drc.rpt
report_methodology -file synth_out/methodology.rpt

write_checkpoint -force synth_out/cnn_accel_top_synth.dcp

puts "============================================================"
puts "Synthesis completed."
puts "Constraint file: constraints/cnn_accel_top.xdc"
puts "Reports written to synth_out/"
puts "============================================================"