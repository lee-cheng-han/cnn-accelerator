#!/usr/bin/env bash
set -euo pipefail

TB=tb_cnn_axi_lite_slave
TOP=${TB}

rm -rf xsim.dir/${TOP}_sim .Xil/${TOP}_sim ${TOP}_sim.wdb
rm -f ${TOP}_xsim_run.log

xvlog -sv \
  rtl/zynq/cnn_axi_lite_slave.sv \
  tb/zynq/${TB}.sv

xelab ${TOP} -s ${TOP}_sim

set +e
xsim ${TOP}_sim -runall | tee ${TOP}_xsim_run.log
XSIM_STATUS=${PIPESTATUS[0]}
set -e

if [[ $XSIM_STATUS -ne 0 ]]; then
  echo "[FAIL] ${TOP}: xsim exited with status $XSIM_STATUS"
  exit $XSIM_STATUS
fi

if grep -E "\[FAIL\]|FAILED|Fatal:|ERROR:" ${TOP}_xsim_run.log >/dev/null; then
  echo "[FAIL] ${TOP}: failure pattern found in simulation log"
  exit 1
fi

if grep -E "\[PASS\]|PASS" ${TOP}_xsim_run.log >/dev/null; then
  echo "[PASS] ${TOP}"
else
  echo "[FAIL] ${TOP}: no PASS message found in simulation log"
  exit 1
fi
