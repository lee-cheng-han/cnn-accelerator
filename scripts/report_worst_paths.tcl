open_checkpoint synth_out/cnn_accel_top_synth.dcp

read_xdc constraints/cnn_accel_top.xdc

report_timing \
  -delay_type max \
  -max_paths 10 \
  -nworst 10 \
  -path_type full_clock_expanded \
  -file synth_out/worst_paths.rpt

puts "Worst paths written to synth_out/worst_paths.rpt"
