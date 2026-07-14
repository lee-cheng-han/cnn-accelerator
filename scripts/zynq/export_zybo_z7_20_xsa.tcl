set proj_name zybo_z7_20_cnn
set proj_dir build/zybo_z7_20_cnn
set xsa_file build/zybo_z7_20_cnn/zybo_z7_20_cnn.xsa
set board_part digilentinc.com:zybo-z7-20:part0:1.2
set board_repo [file normalize board_files]

if {[info exists ::env(PROJ_NAME)]} {
 set proj_name $::env(PROJ_NAME)
}

if {[info exists ::env(PROJ_DIR)]} {
 set proj_dir $::env(PROJ_DIR)
 set xsa_file $proj_dir/$proj_name.xsa
}

set_param board.repoPaths [list $board_repo]
open_project $proj_dir/$proj_name.xpr

if {[get_property BOARD_PART [current_project]] ne $board_part} {
 puts "ERROR: project board part is not $board_part"
 exit 1
}

write_hw_platform -fixed -include_bit -force -file $xsa_file

puts ""
puts "Exported XSA:"
puts " $xsa_file"
puts ""
