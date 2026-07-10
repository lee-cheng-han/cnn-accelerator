#!/usr/bin/env bash
set -euo pipefail

TESTS=(
  tb_v2_parallel_mac_array
  tb_v2_psum_accumulator
  tb_v2_tail_mask_postprocess
  tb_v2_tiled_conv1x1_engine
  tb_v2_tensor_address_gen
  tb_v2_tiled_conv3x3_engine
  tb_v2_scratchpads
  tb_v2_ping_pong_buffers
  tb_v2_tensor_load_controllers
  tb_v2_output_store_controller
  tb_v2_layer_descriptors
  tb_v2_single_layer_scheduler
  tb_v2_multi_layer_job_controller
  tb_v2_stream_loaded_multi_layer_job_controller
  tb_v2_performance_counters
  tb_v2_axi_lite_slave
  tb_v2_axi_stream_top
  tb_v2_image2image_system_top
)

for tb in "${TESTS[@]}"; do
  echo "============================================================"
  echo "[V2 UNIT] $tb"
  echo "============================================================"
  bash scripts/run_v2_unit_tb.sh "$tb"
done

echo "============================================================"
echo "[PASS] v2 unit tests complete"
echo "============================================================"
