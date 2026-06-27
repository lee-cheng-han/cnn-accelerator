setws build/vitis_ws

set xsa_file [file normalize build/arty_z7_20_cnn/arty_z7_20_cnn.xsa]
set app_name cnn_baremetal
set platform_name arty_z7_20_cnn_platform

puts "Using XSA:"
puts "  $xsa_file"

platform create \
    -name $platform_name \
    -hw $xsa_file \
    -proc ps7_cortexa9_0 \
    -os standalone

platform generate

app create \
    -name $app_name \
    -platform $platform_name \
    -domain standalone_domain \
    -template "Hello World"

file copy -force software/zynq_baremetal/main.c build/vitis_ws/$app_name/src/main.c

app build -name $app_name

puts ""
puts "Vitis bare-metal app build done."
puts "ELF:"
puts "  build/vitis_ws/$app_name/Debug/$app_name.elf"
puts ""
