set proj_name zybo_z7_20_cnn
set proj_dir build/zybo_z7_20_cnn
set bd_name system
set board_part digilentinc.com:zybo-z7-20:part0:1.2
set board_repo [file normalize board_files]

if {[info exists ::env(PROJ_NAME)]} {
 set proj_name $::env(PROJ_NAME)
}

if {[info exists ::env(PROJ_DIR)]} {
 set proj_dir $::env(PROJ_DIR)
}

set_param board.repoPaths [list $board_repo]
open_project $proj_dir/$proj_name.xpr

if {[get_property BOARD_PART [current_project]] ne $board_part} {
 puts "ERROR: project board part is not $board_part"
 exit 1
}

update_compile_order -fileset sources_1

generate_target all [get_files $proj_dir/$proj_name.srcs/sources_1/bd/$bd_name/$bd_name.bd]

set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

set synthesis_runs [get_runs -filter {IS_SYNTHESIS == 1}]
reset_run $synthesis_runs
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

report_utilization -file build/zybo_z7_20_bitstream_util.rpt
report_timing_summary -file build/zybo_z7_20_bitstream_timing.rpt

set failing_setup_paths [get_timing_paths -setup -max_paths 1 -slack_lesser_than 0]
set failing_hold_paths [get_timing_paths -hold -max_paths 1 -slack_lesser_than 0]

if {[llength $failing_setup_paths] > 0 || [llength $failing_hold_paths] > 0} {
 puts "ERROR: routed design failed timing constraints"
 exit 1
}

puts ""
puts "ZYBO Z7-20 BITSTREAM BUILD DONE"
puts "Bitstream:"
puts " $proj_dir/$proj_name.runs/impl_1/${bd_name}_wrapper.bit"
puts "Reports:"
puts " build/zybo_z7_20_bitstream_util.rpt"
puts " build/zybo_z7_20_bitstream_timing.rpt"
puts ""
