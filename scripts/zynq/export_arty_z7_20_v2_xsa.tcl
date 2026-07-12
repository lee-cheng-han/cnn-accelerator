set proj_name arty_z7_20_cnn_v2
set proj_dir  build/arty_z7_20_cnn_v2
set xsa_file  build/arty_z7_20_cnn_v2/arty_z7_20_cnn_v2.xsa

if {[info exists ::env(PROJ_NAME)]} {
  set proj_name $::env(PROJ_NAME)
}

if {[info exists ::env(PROJ_DIR)]} {
  set proj_dir $::env(PROJ_DIR)
  set xsa_file $proj_dir/$proj_name.xsa
}

open_project $proj_dir/$proj_name.xpr

write_hw_platform -fixed -include_bit -force -file $xsa_file

puts ""
puts "Exported v2 XSA:"
puts "  $xsa_file"
puts ""
