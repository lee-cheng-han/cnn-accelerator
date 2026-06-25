#!/usr/bin/env bash
set -u

SEED=${SEED:-12345}

TESTS=(
  tb_mac_unit
  tb_mac_array_3x3
  tb_channel_accumulator
  tb_window_generator_3x3
  tb_conv_engine
  tb_cnn_accel_top_small
  tb_cnn_accel_top_random
  tb_streaming_window_buffer
  tb_streaming_cnn_core
  tb_streaming_cnn_core_random
  tb_uart_tx
  tb_uart_rx
  tb_uart_cmd_decoder
  tb_cnn_config_loader
)

PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

mkdir -p regression_logs

echo "============================================================"
echo "CNN ACCELERATOR REGRESSION"
echo "============================================================"
echo "Seed: ${SEED}"
echo "Tests: ${#TESTS[@]}"
echo "============================================================"

for TB in "${TESTS[@]}"; do
  TOTAL_COUNT=$((TOTAL_COUNT + 1))
  LOG="regression_logs/${TB}_seed_${SEED}.log"

  echo ""
  echo "------------------------------------------------------------"
  echo "[RUN] ${TB}"
  echo "------------------------------------------------------------"

  make xsim TB="${TB}" SEED="${SEED}" > "${LOG}" 2>&1
  STATUS=$?

  if grep -q "\[PASS\]" "${LOG}" && [ "${STATUS}" -eq 0 ]; then
    echo "[PASS] ${TB}"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "[FAIL] ${TB}"
    echo "Log: ${LOG}"
    tail -80 "${LOG}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

echo ""
echo "================================================------------"
echo "REGRESSION SUMMARY"
echo "================================================------------"
echo "Total tests : ${TOTAL_COUNT}"
echo "Passed      : ${PASS_COUNT}"
echo "Failed      : ${FAIL_COUNT}"
echo "Seed        : ${SEED}"
echo "================================================------------"

if [ "${FAIL_COUNT}" -eq 0 ]; then
  echo "[PASS] Full regression passed"
  exit 0
else
  echo "[FAIL] Full regression failed"
  exit 1
fi

  tb_cnn_accel_board_top_compile
  tb_cnn_accel_board_top_invalid
  tb_cnn_accel_board_top_e2e
