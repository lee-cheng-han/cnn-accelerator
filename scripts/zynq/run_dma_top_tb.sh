#!/usr/bin/env bash
set -euo pipefail

VIVADO="${VIVADO:-$HOME/Xilinx/2025.2/Vivado/bin}"

cd "$(dirname "$0")/../.."

rm -rf xsim.dir tb_cnn_dma_system_top_sim.wdb tb_cnn_dma_system_top_sim
rm -f tb_cnn_dma_system_top_xsim_run.log

"$VIVADO/xvlog" -sv \
tb/stream/axi_protocol_assertions.sv \
rtl/zynq/cnn_axi_lite_slave.sv \
rtl/fpga/cnn_config_loader.sv \
rtl/stream/axis_rgb_to_channels.sv \
rtl/stream/axis_output_widen.sv \
rtl/buffer/line_buffer_3x3.sv \
rtl/buffer/window_generator_3x3.sv \
rtl/compute/conv_engine.sv \
rtl/fpga/streaming_window_buffer.sv \
rtl/fpga/streaming_cnn_core.sv \
rtl/zynq/cnn_dma_system_top.sv \
tb/stream/tb_cnn_dma_system_top.sv

"$VIVADO/xelab" tb_cnn_dma_system_top -s tb_cnn_dma_system_top_sim

set +e
"$VIVADO/xsim" tb_cnn_dma_system_top_sim -runall | tee tb_cnn_dma_system_top_xsim_run.log
XSIM_STATUS=${PIPESTATUS[0]}
set -e

if [[ $XSIM_STATUS -ne 0 ]]; then
  echo "[FAIL] tb_cnn_dma_system_top: xsim exited with status $XSIM_STATUS"
  exit $XSIM_STATUS
fi

if grep -E "\[FAIL\]|FAILED|Fatal:|ERROR:" tb_cnn_dma_system_top_xsim_run.log >/dev/null; then
  echo "[FAIL] tb_cnn_dma_system_top: failure pattern found in simulation log"
  exit 1
fi

if grep -E "\[PASS\]|PASS" tb_cnn_dma_system_top_xsim_run.log >/dev/null; then
  echo "[PASS] tb_cnn_dma_system_top"
else
  echo "[FAIL] tb_cnn_dma_system_top: no PASS message found in simulation log"
  exit 1
fi
