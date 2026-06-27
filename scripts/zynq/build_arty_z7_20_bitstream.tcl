set proj_name arty_z7_20_cnn
set proj_dir  build/arty_z7_20_cnn
set bd_name   system

open_project $proj_dir/$proj_name.xpr

update_compile_order -fileset sources_1

# Generate block design output products
generate_target all [get_files $proj_dir/$proj_name.srcs/sources_1/bd/$bd_name/$bd_name.bd]

# Make sure wrapper is top
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

# Run synthesis
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
  puts "ERROR: synthesis did not complete"
  exit 1
}

# Run implementation
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
  puts "ERROR: implementation/bitstream did not complete"
  exit 1
}

open_run impl_1

report_utilization -file build/arty_z7_20_bitstream_util.rpt
report_timing_summary -file build/arty_z7_20_bitstream_timing.rpt

puts ""
puts "ARTY Z7-20 BITSTREAM BUILD DONE"
puts "Bitstream:"
puts "  $proj_dir/$proj_name.runs/impl_1/${bd_name}_wrapper.bit"
puts "Reports:"
puts "  build/arty_z7_20_bitstream_util.rpt"
puts "  build/arty_z7_20_bitstream_timing.rpt"
puts ""
