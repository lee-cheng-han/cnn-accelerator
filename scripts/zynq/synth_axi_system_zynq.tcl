set part_name xc7z020clg400-1
set top_name cnn_axi_system_top
set proj_dir build/zynq_axi_system_synth

file delete -force $proj_dir
create_project zynq_axi_system_synth $proj_dir -part $part_name

set rtl_files [glob -nocomplain \
  rtl/compute/*.sv \
  rtl/fpga/cnn_config_loader.sv \
  rtl/fpga/output_result_buffer.sv \
  rtl/fpga/streaming_cnn_core.sv \
  rtl/fpga/streaming_window_buffer.sv \
  rtl/zynq/cnn_axi_lite_slave.sv \
  rtl/zynq/cnn_axi_system_top.sv \
]

add_files -norecurse $rtl_files
set_property top $top_name [current_fileset]

update_compile_order -fileset sources_1

synth_design -top $top_name -part $part_name

report_utilization -file build/zynq_axi_system_synth_util.rpt
report_timing_summary -file build/zynq_axi_system_synth_timing.rpt

puts ""
puts "ZYNQ AXI SYSTEM SYNTHESIS DONE"
puts "Reports:"
puts "  build/zynq_axi_system_synth_util.rpt"
puts "  build/zynq_axi_system_synth_timing.rpt"
puts ""
