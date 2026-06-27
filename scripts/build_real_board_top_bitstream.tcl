set part_name xc7z020clg400-1
set top_name cnn_accel_board_top

proc find_sv_files {dir} {
  set files [list]

  foreach f [glob -nocomplain -directory $dir *.sv] {
    lappend files $f
  }

  foreach subdir [glob -nocomplain -type d -directory $dir *] {
    foreach f [find_sv_files $subdir] {
      lappend files $f
    }
  }

  return $files
}

set sv_files [find_sv_files rtl]

read_verilog -sv $sv_files

synth_design \
  -top $top_name \
  -part $part_name \
  -generic CLK_FREQ_HZ=125000000 \
  -generic BAUD_RATE=115200 \
  -generic RESULT_DEPTH=16384 \
  -flatten_hierarchy none

create_clock -period 8.000 -name clk [get_ports clk]

# Add your real board XDC here later:
read_xdc constraints/arty_z7_20_pmod_uart.xdc

opt_design
place_design
route_design

file mkdir build/real_board_top

report_utilization -file build/real_board_top/utilization_post_route.rpt
report_timing_summary -file build/real_board_top/timing_post_route.rpt

write_checkpoint -force build/real_board_top/real_board_top_routed.dcp
write_bitstream -force build/real_board_top/cnn_accel_board_top.bit

exit
