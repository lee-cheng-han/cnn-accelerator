#!/usr/bin/env bash
set -euo pipefail

if ! command -v verilator >/dev/null 2>&1; then
 echo "ERROR: verilator not found"
 exit 1
fi

build_dir="sim/verilator/requantizer"
rm -rf "$build_dir"
mkdir -p "$build_dir"

verilator --binary --timing \
 -Wall \
 -Wno-fatal \
 -Wno-BLKSEQ \
 --top-module tb_parallel_requantizer \
 rtl/postprocess/parallel_requantizer.sv \
 tb/tb_parallel_requantizer.sv \
 --Mdir "$build_dir"

"$build_dir/Vtb_parallel_requantizer"
