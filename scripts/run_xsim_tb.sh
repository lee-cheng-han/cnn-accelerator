#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   bash scripts/run_xsim_tb.sh tb_mac_unit
#   bash scripts/run_xsim_tb.sh tb/tb_mac_unit.sv
#
# Optional:
#   SEED=12345 bash scripts/run_xsim_tb.sh tb_mac_unit

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <testbench_name|tb/testbench_file.sv>"
  echo "Example: $0 tb_mac_unit"
  exit 1
fi

TB_ARG="$1"
SEED="${SEED:-12345}"

# Allow either tb_mac_unit or tb/tb_mac_unit.sv
TB_NAME="$(basename "$TB_ARG" .sv)"
TB_FILE="tb/${TB_NAME}.sv"

if [[ ! -f "$TB_FILE" ]]; then
  echo "ERROR: Could not find testbench file: $TB_FILE"
  exit 1
fi

if ! command -v xvlog >/dev/null 2>&1; then
  echo "ERROR: xvlog not found. Source Vivado settings first, for example:"
  echo "source ~/Xilinx/2025.2/Vivado/settings64.sh"
  exit 1
fi

if ! command -v xelab >/dev/null 2>&1; then
  echo "ERROR: xelab not found. Source Vivado settings first."
  exit 1
fi

if ! command -v xsim >/dev/null 2>&1; then
  echo "ERROR: xsim not found. Source Vivado settings first."
  exit 1
fi

mkdir -p sim/xsim
rm -rf \
  sim/xsim/${TB_NAME}_xsim.dir \
  sim/xsim/${TB_NAME}.jou \
  sim/xsim/${TB_NAME}.log \
  sim/xsim/${TB_NAME}_xsim_run.log \
  sim/xsim/xvlog.log \
  sim/xsim/xelab.log \
  sim/xsim/xsim.log

cd sim/xsim

echo "[XSim] Compiling RTL and $TB_FILE"

xvlog -sv -L work \
  ../../rtl/cnn_accel_pkg.sv \
  ../../rtl/postprocess/bias_add.sv \
  ../../rtl/postprocess/relu.sv \
  ../../rtl/postprocess/quantizer.sv \
  ../../rtl/postprocess/output_saturate.sv \
  ../../rtl/compute/mac_unit.sv \
  ../../rtl/compute/mac_array_3x3.sv \
  ../../rtl/compute/adder_tree.sv \
  ../../rtl/compute/channel_accumulator.sv \
  ../../rtl/compute/conv_engine.sv \
  ../../rtl/compute/output_channel_array.sv \
  ../../rtl/control/config_regs.sv \
  ../../rtl/control/accel_controller.sv \
  ../../rtl/control/perf_counters.sv \
  ../../rtl/stream/stream_fifo.sv \
  ../../rtl/stream/axis_input_if.sv \
  ../../rtl/stream/axis_output_if.sv \
  ../../rtl/buffer/activation_buffer.sv \
  ../../rtl/buffer/weight_buffer.sv \
  ../../rtl/buffer/line_buffer_3x3.sv \
  ../../rtl/buffer/window_generator_3x3.sv \
  ../../rtl/fpga/*.sv \
  ../../rtl/cnn_accel_top.sv \
  ../../${TB_FILE}

echo "[XSim] Elaborating $TB_NAME"

xelab -debug typical ${TB_NAME} -s ${TB_NAME}_sim

echo "[XSim] Running $TB_NAME with ntb_random_seed=$SEED"

set +e
xsim ${TB_NAME}_sim -testplusarg "ntb_random_seed=${SEED}" -runall | tee ${TB_NAME}_xsim_run.log
XSIM_STATUS=${PIPESTATUS[0]}
set -e

if [[ $XSIM_STATUS -ne 0 ]]; then
  echo "[FAIL] $TB_NAME: xsim exited with status $XSIM_STATUS"
  exit $XSIM_STATUS
fi

# Catch testbench failures that XSim may not return as a nonzero exit code.
if grep -E "\[FAIL\]|FAILED|Fatal:|ERROR:" ${TB_NAME}_xsim_run.log >/dev/null; then
  echo "[FAIL] $TB_NAME: failure pattern found in simulation log"
  exit 1
fi

# Require an explicit PASS message from the testbench.
if grep -E "\[PASS\]|PASS" ${TB_NAME}_xsim_run.log >/dev/null; then
  echo "[PASS] $TB_NAME"
else
  echo "[FAIL] $TB_NAME: no PASS message found in simulation log"
  exit 1
fi