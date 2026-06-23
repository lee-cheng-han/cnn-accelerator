#!/usr/bin/env bash
set -euo pipefail

TESTS=(
  tb_mac_unit
  tb_mac_array_3x3
  tb_channel_accumulator
  tb_conv_engine
  tb_line_buffer_3x3
  tb_window_generator_3x3
  tb_cnn_accel_top_small
  tb_cnn_accel_top_random
)

for tb in "${TESTS[@]}"; do
  echo "============================================================"
  echo "[REGRESSION] $tb"
  echo "============================================================"
  bash scripts/run_xsim_tb.sh "$tb"
done

echo "============================================================"
echo "[PASS] XSim regression complete"
echo "============================================================"
