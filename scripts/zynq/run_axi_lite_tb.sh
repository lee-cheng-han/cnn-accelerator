#!/usr/bin/env bash
set -euo pipefail

TB=tb_cnn_axi_lite_slave
TOP=${TB}

rm -rf xsim.dir/${TOP}_sim .Xil/${TOP}_sim ${TOP}_sim.wdb

xvlog -sv \
  rtl/zynq/cnn_axi_lite_slave.sv \
  tb/zynq/${TB}.sv

xelab ${TOP} -s ${TOP}_sim

xsim ${TOP}_sim -runall
