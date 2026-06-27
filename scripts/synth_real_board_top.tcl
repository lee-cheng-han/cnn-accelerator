set part_name xc7a35tcpg236-1
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

puts "Reading SystemVerilog files:"
foreach f $sv_files {
  puts "  $f"
}

read_verilog -sv $sv_files

synth_design \
  -top $top_name \
  -part $part_name \
  -generic CLK_FREQ_HZ=100000000 \
  -generic BAUD_RATE=115200 \
  -generic RESULT_DEPTH=16384 \
  -flatten_hierarchy none

create_clock -period 10.000 -name clk [get_ports clk]

file mkdir synth_out/real_board_top

report_utilization \
  -hierarchical \
  -file synth_out/real_board_top/utilization.rpt

report_utilization \
  -file synth_out/real_board_top/utilization_full.rpt

report_timing_summary \
  -file synth_out/real_board_top/timing_summary.rpt

write_checkpoint \
  -force synth_out/real_board_top/real_board_top_synth.dcp

exit
