set proj_name arty_z7_20_cnn_v2
set proj_dir  build/arty_z7_20_cnn_v2
set bd_name   system

if {[info exists ::env(PROJ_NAME)]} {
  set proj_name $::env(PROJ_NAME)
}

if {[info exists ::env(PROJ_DIR)]} {
  set proj_dir $::env(PROJ_DIR)
}

open_project $proj_dir/$proj_name.xpr

update_compile_order -fileset sources_1

generate_target all [get_files $proj_dir/$proj_name.srcs/sources_1/bd/$bd_name/$bd_name.bd]

set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
  puts "ERROR: synthesis did not complete"
  exit 1
}

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
  puts "ERROR: implementation/bitstream did not complete"
  exit 1
}

open_run impl_1

report_utilization -file build/arty_z7_20_v2_bitstream_util.rpt
report_timing_summary -file build/arty_z7_20_v2_bitstream_timing.rpt

puts ""
puts "ARTY Z7-20 V2 BITSTREAM BUILD DONE"
puts "Bitstream:"
puts "  $proj_dir/$proj_name.runs/impl_1/${bd_name}_wrapper.bit"
puts "Reports:"
puts "  build/arty_z7_20_v2_bitstream_util.rpt"
puts "  build/arty_z7_20_v2_bitstream_timing.rpt"
puts ""
