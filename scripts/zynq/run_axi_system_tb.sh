#!/usr/bin/env bash
set -euo pipefail

TB=tb_cnn_axi_system_top
TOP=${TB}

rm -rf xsim.dir/${TOP}_sim .Xil/${TOP}_sim ${TOP}_sim.wdb

RTL_FILES=$(find rtl -name "*.sv" | sort)

xvlog -sv ${RTL_FILES} tb/zynq/${TB}.sv

xelab ${TOP} -s ${TOP}_sim

xsim ${TOP}_sim -runall
