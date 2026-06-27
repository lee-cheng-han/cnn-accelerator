set proj_name arty_z7_20_cnn
set proj_dir  build/arty_z7_20_cnn
set xsa_file  build/arty_z7_20_cnn/arty_z7_20_cnn.xsa

open_project $proj_dir/$proj_name.xpr

write_hw_platform -fixed -include_bit -force -file $xsa_file

puts ""
puts "Exported XSA:"
puts "  $xsa_file"
puts ""
