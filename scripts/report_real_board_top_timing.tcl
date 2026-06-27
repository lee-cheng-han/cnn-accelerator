open_checkpoint synth_out/real_board_top/real_board_top_synth.dcp

report_timing \
  -max_paths 10 \
  -sort_by slack \
  -path_type full \
  -file synth_out/real_board_top/worst_paths.rpt

exit
