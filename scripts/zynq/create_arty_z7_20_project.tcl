set part_name xc7z020clg400-1
set proj_name arty_z7_20_cnn
set proj_dir  build/arty_z7_20_cnn
set bd_name   system

if {[info exists ::env(PROJ_NAME)]} {
  set proj_name $::env(PROJ_NAME)
}

if {[info exists ::env(PROJ_DIR)]} {
  set proj_dir $::env(PROJ_DIR)
}

set enable_ila 0
if {[info exists ::env(ENABLE_ILA)] && ($::env(ENABLE_ILA) eq "1")} {
  set enable_ila 1
}

file delete -force $proj_dir

create_project $proj_name $proj_dir -part $part_name

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

# Add RTL source files
set rtl_files [glob -nocomplain \
  rtl/compute/*.sv \
  rtl/buffer/*.sv \
  rtl/stream/*.sv \
  rtl/fpga/cnn_config_loader.sv \
  rtl/fpga/streaming_cnn_core.sv \
  rtl/fpga/streaming_window_buffer.sv \
  rtl/zynq/cnn_axi_lite_slave.sv \
  rtl/zynq/cnn_dma_system_top.sv \
  rtl/zynq/cnn_dma_system_bd_wrapper.v \
]

add_files -norecurse $rtl_files
update_compile_order -fileset sources_1

# Create block design
create_bd_design $bd_name
current_bd_design $bd_name

# Zynq Processing System
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 ps7

# Enable PS UART1 for bare-metal UART prints over the Arty Z7 USB-UART path.
set_property -dict [list \
  CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
  CONFIG.PCW_UART1_UART1_IO {MIO 48 .. 49} \
  CONFIG.PCW_UART_PERIPHERAL_FREQMHZ {100} \
] [get_bd_cells ps7]

# Apply basic Zynq config
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
  -config {make_external "FIXED_IO, DDR" apply_board_preset "0" Master "Disable" Slave "Disable"} \
  [get_bd_cells ps7]

# Enable GP0 AXI master, HP0 AXI slave, and FCLK0
set_property -dict [list \
  CONFIG.PCW_USE_M_AXI_GP0 {1} \
  CONFIG.PCW_USE_S_AXI_HP0 {1} \
  CONFIG.PCW_EN_CLK0_PORT {1} \
  CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100.0} \
] [get_bd_cells ps7]

# Processor reset block
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_ps7_0

# AXI-Lite interconnect: PS GP0 -> CNN config + AXI DMA config
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect axi_lite_interconnect
set_property -dict [list \
  CONFIG.NUM_MI {2} \
  CONFIG.NUM_SI {1} \
] [get_bd_cells axi_lite_interconnect]

# AXI memory interconnect: AXI DMA MM2S/S2MM -> PS HP0 DDR port
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect axi_mem_interconnect
set_property -dict [list \
  CONFIG.NUM_MI {1} \
  CONFIG.NUM_SI {2} \
] [get_bd_cells axi_mem_interconnect]

# AXI DMA
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma axi_dma_0
set_property -dict [list \
  CONFIG.c_include_sg {0} \
  CONFIG.c_include_mm2s {1} \
  CONFIG.c_include_s2mm {1} \
  CONFIG.c_m_axi_mm2s_data_width {32} \
  CONFIG.c_m_axis_mm2s_tdata_width {32} \
  CONFIG.c_s_axis_s2mm_tdata_width {32} \
  CONFIG.c_sg_include_stscntrl_strm {0} \
] [get_bd_cells axi_dma_0]

# CNN DMA-capable RTL module
create_bd_cell -type module -reference cnn_dma_system_bd_wrapper cnn_axi_0

# Clock/reset connections
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins rst_ps7_0/slowest_sync_clk]

connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/M_AXI_GP0_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/S_AXI_HP0_ACLK]

connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_lite_interconnect/ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_lite_interconnect/S00_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_lite_interconnect/M00_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_lite_interconnect/M01_ACLK]

connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_mem_interconnect/ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_mem_interconnect/S00_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_mem_interconnect/S01_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_mem_interconnect/M00_ACLK]

connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_dma_0/s_axi_lite_aclk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_dma_0/m_axi_mm2s_aclk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins axi_dma_0/m_axi_s2mm_aclk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins cnn_axi_0/s_axi_aclk]

connect_bd_net [get_bd_pins ps7/FCLK_RESET0_N] [get_bd_pins rst_ps7_0/ext_reset_in]

connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins axi_lite_interconnect/ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins axi_lite_interconnect/S00_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins axi_lite_interconnect/M00_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins axi_lite_interconnect/M01_ARESETN]

connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins axi_mem_interconnect/ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins axi_mem_interconnect/S00_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins axi_mem_interconnect/S01_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins axi_mem_interconnect/M00_ARESETN]

connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins axi_dma_0/axi_resetn]
connect_bd_net [get_bd_pins rst_ps7_0/peripheral_aresetn] [get_bd_pins cnn_axi_0/s_axi_aresetn]

# AXI-Lite connections
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins axi_lite_interconnect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_lite_interconnect/M00_AXI] [get_bd_intf_pins cnn_axi_0/S_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_lite_interconnect/M01_AXI] [get_bd_intf_pins axi_dma_0/S_AXI_LITE]

# AXI DMA memory connections to PS DDR through HP0
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] [get_bd_intf_pins axi_mem_interconnect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] [get_bd_intf_pins axi_mem_interconnect/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_mem_interconnect/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP0]

# AXI-Stream connections
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins cnn_axi_0/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins cnn_axi_0/M_AXIS] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

if {$enable_ila} {
  puts "ENABLE_ILA=1: adding System ILA interface monitors"

  create_bd_cell -type ip -vlnv xilinx.com:ip:system_ila ila_cnn_axis
  set_property -dict [list \
    CONFIG.C_MON_TYPE {INTERFACE} \
    CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_NUM_MONITOR_SLOTS {3} \
    CONFIG.C_SLOT_0_INTF_TYPE {xilinx.com:interface:axis_rtl:1.0} \
    CONFIG.C_SLOT_1_INTF_TYPE {xilinx.com:interface:axis_rtl:1.0} \
    CONFIG.C_SLOT_2_INTF_TYPE {xilinx.com:interface:aximm_rtl:1.0} \
  ] [get_bd_cells ila_cnn_axis]

  connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ila_cnn_axis/clk]

  connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins ila_cnn_axis/SLOT_0_AXIS]
  connect_bd_intf_net [get_bd_intf_pins cnn_axi_0/M_AXIS]      [get_bd_intf_pins ila_cnn_axis/SLOT_1_AXIS]
  connect_bd_intf_net [get_bd_intf_pins cnn_axi_0/S_AXI]       [get_bd_intf_pins ila_cnn_axis/SLOT_2_AXI]
}

# Address map: CNN AXI-Lite at 0x43C00000
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

# Address map: AXI DMA control registers at 0x40400000
set dma_lite_seg [get_bd_addr_segs -quiet /axi_dma_0/S_AXI_LITE/Reg]

if {[llength $dma_lite_seg] < 1} {
  puts "ERROR: Could not find AXI DMA control segment /axi_dma_0/S_AXI_LITE/Reg"
  puts "Available address segments:"
  puts [get_bd_addr_segs -hier]
  exit 1
}

assign_bd_address \
  -offset 0x40400000 \
  -range 0x00010000 \
  -target_address_space [get_bd_addr_spaces ps7/Data] \
  $dma_lite_seg \
  -force

# Let Vivado assign DDR address segments for DMA masters.
assign_bd_address

puts "CNN AXI-Lite slave assigned to 0x43C00000, range 4K"
puts "AXI DMA control assigned to 0x40400000, range 64K"

# Validate and save
validate_bd_design
save_bd_design

# Generate HDL wrapper
make_wrapper -files [get_files $proj_dir/$proj_name.srcs/sources_1/bd/$bd_name/$bd_name.bd] -top
add_files -norecurse $proj_dir/$proj_name.gen/sources_1/bd/$bd_name/hdl/${bd_name}_wrapper.v
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts ""
puts "ARTY Z7-20 DMA BLOCK DESIGN CREATED"
puts "Project:"
puts "  $proj_dir/$proj_name.xpr"
puts "Block design:"
puts "  $bd_name"
puts "CNN base address:"
puts "  0x43C00000"
puts "AXI DMA base address:"
puts "  0x40400000"
if {$enable_ila} {
  puts "ILA debug core:"
  puts "  ila_cnn_axis"
}
puts ""
