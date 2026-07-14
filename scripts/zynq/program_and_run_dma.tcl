set bit_file "build/zybo_z7_20_cnn/zybo_z7_20_cnn.runs/impl_1/system_wrapper.bit"
set elf_file "build/vitis_ws/cnn_baremetal/build/cnn_baremetal.elf"

set ps7_init_file "build/vitis_ws/zybo_z7_20_cnn_platform/export/zybo_z7_20_cnn_platform/hw/sdt/ps7_init.tcl"

if {![file exists $ps7_init_file]} {
 puts "ERROR: Could not find Zybo Z7-20 ps7_init.tcl"
 exit 1
}

puts "Using bitstream:"
puts " $bit_file"
puts "Using ELF:"
puts " $elf_file"
puts "Using PS init:"
puts " $ps7_init_file"

connect

puts "Programming FPGA..."
fpga -file $bit_file

puts "Initializing Zynq PS..."
source $ps7_init_file

targets -set -nocase -filter {name =~ "Cortex-A9 #0"}

rst -processor
after 1000

ps7_init
ps7_post_config

puts "Downloading ELF..."
dow $elf_file

puts "Running ELF..."
con

puts " program started. Check UART output."
