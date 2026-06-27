set part_name xc7z020clg400-1
set proj_name arty_z7_20_cnn
set proj_dir  build/arty_z7_20_cnn
set bd_name   system

file delete -force $proj_dir

create_project $proj_name $proj_dir -part $part_name

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

# Add RTL source files
set rtl_files [glob -nocomplain \
  rtl/compute/*.sv \
  rtl/fpga/cnn_config_loader.sv \
  rtl/fpga/output_result_buffer.sv \
  rtl/fpga/streaming_cnn_core.sv \
  rtl/fpga/streaming_window_buffer.sv \
  rtl/zynq/cnn_axi_lite_slave.sv \
  rtl/zynq/cnn_axi_system_top.sv \
  rtl/zynq/cnn_axi_system_bd_wrapper.v \
]

add_files -norecurse $rtl_files
update_compile_order -fileset sources_1

# Create block design
create_bd_design $bd_name
current_bd_design $bd_name

# Zynq Processing System
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 ps7

# Enable PS UART1 for bare-metal UART prints over the Arty Z7 USB-UART path.
# Arty Z7 uses the Zynq PS UART through MIO, so Vitis needs this peripheral
# present in the exported XSA.
set_property -dict [list \
  CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
  CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49} \
  CONFIG.PCW_UART_PERIPHERAL_FREQMHZ {100} \
] [get_bd_cells ps7]

# Apply basic Zynq config
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
  -config {make_external "FIXED_IO, DDR" apply_board_preset "0" Master "Disable" Slave "Disable"} \
  [get_bd_cells ps7]

# Enable GP0 AXI master and FCLK0
set_property -dict [list \
  CONFIG.PCW_USE_M_AXI_GP0 {1} \
  CONFIG.PCW_USE_S_AXI_GP0 {0} \
  CONFIG.PCW_EN_CLK0_PORT {1} \
  CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100.0} \
] [get_bd_cells ps7]

# Processor reset block
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_ps7_0

# AXI interconnect
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect axi_interconnect_0
set_property -dict [list \
  CONFIG.NUM_MI {1} \
  CONFIG.NUM_SI {1} \
] [get_bd_cells axi_interconnect_0]

# Add your RTL module as a block design module reference
create_bd_cell -type module -reference cnn_axi_system_bd_wrapper cnn_axi_0

# Clock/reset connections
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins rst_ps7_0/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/M_AXI_GP0_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_interconnect_0/ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_interconnect_0/S00_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_interconnect_0/M00_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins cnn_axi_0/s_axi_aclk]

connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins rst_ps7_0/ext_reset_in]
connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins axi_interconnect_0/ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins axi_interconnect_0/S00_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins axi_interconnect_0/M00_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins cnn_axi_0/s_axi_aresetn]

# AXI connections
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins axi_interconnect_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M00_AXI] [get_bd_intf_pins cnn_axi_0/S_AXI]

# Address map
# Directly assign the CNN AXI-Lite slave into the Zynq PS address space.
set cnn_slave_seg [get_bd_addr_segs -quiet /cnn_axi_0/s_axi/reg0]

if {[llength $cnn_slave_seg] < 1} {
  puts "ERROR: Could not find CNN slave segment /cnn_axi_0/s_axi/reg0"
  puts "Available address segments:"
  puts [get_bd_addr_segs -hier]
  exit 1
}

assign_bd_address \
  -offset 0x43C00000 \
  -range 0x00001000 \
  -target_address_space [get_bd_addr_spaces ps7/Data] \
  $cnn_slave_seg \
  -force

puts "CNN AXI-Lite slave assigned to 0x43C00000, range 4K"

# Validate and save
validate_bd_design
save_bd_design

# Generate HDL wrapper
make_wrapper -files [get_files $proj_dir/$proj_name.srcs/sources_1/bd/$bd_name/$bd_name.bd] -top
add_files -norecurse $proj_dir/$proj_name.gen/sources_1/bd/$bd_name/hdl/${bd_name}_wrapper.v
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts ""
puts "ARTY Z7-20 BLOCK DESIGN CREATED"
puts "Project:"
puts "  $proj_dir/$proj_name.xpr"
puts "Block design:"
puts "  $bd_name"
puts "CNN base address:"
puts "  0x43C00000"
puts ""
