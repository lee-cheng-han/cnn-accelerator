#!/usr/bin/env bash
set -euo pipefail

if ! command -v verilator >/dev/null 2>&1; then
  echo "ERROR: verilator not found."
  echo "Install it with:"
  echo "  sudo apt update"
  echo "  sudo apt install verilator -y"
  exit 1
fi

verilator --lint-only \
  -Wall \
  -Wno-fatal \
  -Wno-UNUSEDSIGNAL \
  -Wno-UNUSEDPARAM \
  --top-module cnn_accel_top \
  rtl/cnn_accel_pkg.sv \
  rtl/postprocess/bias_add.sv \
  rtl/postprocess/relu.sv \
  rtl/postprocess/quantizer.sv \
  rtl/postprocess/output_saturate.sv \
  rtl/compute/mac_unit.sv \
  rtl/compute/mac_array_3x3.sv \
  rtl/compute/adder_tree.sv \
  rtl/compute/channel_accumulator.sv \
  rtl/compute/conv_engine.sv \
  rtl/compute/output_channel_array.sv \
  rtl/control/config_regs.sv \
  rtl/control/accel_controller.sv \
  rtl/control/perf_counters.sv \
  rtl/stream/stream_fifo.sv \
  rtl/stream/axis_input_if.sv \
  rtl/stream/axis_output_if.sv \
  rtl/buffer/activation_buffer.sv \
  rtl/buffer/weight_buffer.sv \
  rtl/buffer/line_buffer_3x3.sv \
  rtl/buffer/window_generator_3x3.sv \
  rtl/cnn_accel_top.sv

echo "[PASS] Verilator lint completed"