SHELL := /bin/bash

TB ?= tb_cnn_accel_top_small
SEED ?= 12345
VITIS_DATA_DIR ?= $(CURDIR)/build/vitis_data

.PHONY: xsim regression xsim-regression lint vectors synth clean flow-report report-flow check-warnings preboard-proof

xsim:
	SEED=$(SEED) bash scripts/run_xsim_tb.sh $(TB)

regression:
	SEED=$(SEED) bash scripts/run_xsim_regression.sh

xsim-regression:
	SEED=$(SEED) bash scripts/run_xsim_regression.sh

.PHONY: v2-unit v2-model-test v2-golden-test v2-regression v2-synth-sweep v2-synth-report

v2-unit:
	bash scripts/run_v2_unit.sh

v2-model-test:
	python3 tests/test_image2image_int8.py

v2-golden-test:
	python3 models/generate_v2_golden_tensors.py
	bash scripts/run_v2_unit_tb.sh tb_v2_golden_tensor_flow
	bash scripts/run_v2_unit_tb.sh tb_v2_full_network_golden_flow
	bash scripts/run_v2_unit_tb.sh tb_v2_stream_loaded_full_network_golden_flow
	bash scripts/run_v2_unit_tb.sh tb_v2_axi_stream_full_network_golden_flow

v2-regression: v2-model-test v2-golden-test v2-unit

v2-synth-sweep:
	bash scripts/v2/run_synth_sweep.sh

v2-synth-report:
	python3 scripts/v2/report_synth_sweep.py --sweep-root build/v2_synth_sweep --markdown docs/v2_synthesis_experiments.md

lint:
	bash scripts/lint_verilator.sh

vectors:
	python3 models/generate_vectors.py

synth:
	vivado -mode batch -source scripts/synth_vivado.tcl

clean:
	rm -rf sim .Xil
	rm -f *.jou *.log *.pb *.vcd

flow-report:
	python3 scripts/report_flow.py

report-flow: flow-report

check-warnings:
	python3 scripts/check_vivado_warnings.py

.PHONY: axi-lite zynq-axi-lite

axi-lite:
	./scripts/zynq/run_axi_lite_tb.sh

zynq-axi-lite: axi-lite

.PHONY: axi-system zynq-axi-system

axi-system:
	./scripts/zynq/run_axi_system_tb.sh

zynq-axi-system: axi-system

.PHONY: zynq-regression

zynq-regression:
	$(MAKE) axi-lite
	$(MAKE) axi-system

.PHONY: synth-zynq-axi-system

synth-zynq-axi-system:
	$(HOME)/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/zynq/synth_axi_system_zynq.tcl

.PHONY: vitis-app clean-vitis clean-generated full-arty-z7-flow

vitis-app:
	rm -rf build/vitis_ws
	mkdir -p $(VITIS_DATA_DIR)
	XILINX_VITIS_DATA_DIR=$(VITIS_DATA_DIR) $(HOME)/Xilinx/2025.2/Vitis/bin/vitis -source scripts/vitis/create_zynq_baremetal_app.py

clean-vitis:
	rm -rf build/vitis_ws

clean-generated:
	rm -rf build
	rm -rf .Xil
	rm -rf xsim.dir
	rm -f *.jou *.log *.str *.wdb *.rpt *.vcd *.fst

full-arty-z7-flow:
	$(MAKE) arty-z7-project
	$(MAKE) arty-z7-bitstream
	$(MAKE) arty-z7-xsa
	$(MAKE) vitis-app

# ==============================
# Zynq Arty Z7-20 DMA Flow
# ==============================

.PHONY: dma-sim
dma-sim:
	bash scripts/zynq/run_dma_top_tb.sh

.PHONY: arty-z7-project
arty-z7-project:
	$(HOME)/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/zynq/create_arty_z7_20_project.tcl

.PHONY: arty-z7-ila-project
arty-z7-ila-project:
	ENABLE_ILA=1 PROJ_NAME=arty_z7_20_cnn_ila PROJ_DIR=build/arty_z7_20_cnn_ila $(HOME)/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/zynq/create_arty_z7_20_project.tcl

.PHONY: arty-z7-bitstream
arty-z7-bitstream:
	$(HOME)/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/zynq/build_arty_z7_20_bitstream.tcl

.PHONY: arty-z7-ila-bitstream
arty-z7-ila-bitstream:
	$(MAKE) arty-z7-ila-project
	PROJ_NAME=arty_z7_20_cnn_ila PROJ_DIR=build/arty_z7_20_cnn_ila $(HOME)/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/zynq/build_arty_z7_20_bitstream.tcl

.PHONY: arty-z7-xsa
arty-z7-xsa:
	$(HOME)/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/zynq/export_arty_z7_20_xsa.tcl

.PHONY: vitis-dma-app
vitis-dma-app:
	mkdir -p $(VITIS_DATA_DIR)
	XILINX_VITIS_DATA_DIR=$(VITIS_DATA_DIR) $(HOME)/Xilinx/2025.2/Vitis/bin/vitis -s scripts/vitis/create_zynq_baremetal_app.py

.PHONY: boot-image
boot-image:
	bash scripts/zynq/create_boot_image.sh

.PHONY: full-arty-z7-dma-flow
full-arty-z7-dma-flow:
	python3 scripts/image/generate_test_headers.py --width 8 --height 8 --kernel 3x3
	$(MAKE) dma-sim
	$(MAKE) arty-z7-project
	$(MAKE) arty-z7-bitstream
	$(MAKE) arty-z7-xsa
	$(MAKE) vitis-dma-app

preboard-proof:
	python3 scripts/image/generate_test_headers.py --width 8 --height 8 --kernel 3x3
	$(MAKE) dma-sim
	$(MAKE) arty-z7-project
	$(MAKE) arty-z7-bitstream
	$(MAKE) arty-z7-xsa
	$(MAKE) vitis-dma-app
	$(MAKE) boot-image
	$(MAKE) check-warnings
	$(MAKE) flow-report

.PHONY: program-arty-z7-dma
program-arty-z7-dma:
	$(HOME)/Xilinx/2025.2/Vitis/bin/xsct scripts/zynq/program_and_run_dma.tcl


# ==============================
# UART Image Streaming App
# ==============================

.PHONY: vitis-uart-image-app
vitis-uart-image-app:
	mkdir -p $(VITIS_DATA_DIR)
	XILINX_VITIS_DATA_DIR=$(VITIS_DATA_DIR) $(HOME)/Xilinx/2025.2/Vitis/bin/vitis -s scripts/vitis/create_zynq_uart_image_app.py

.PHONY: program-arty-z7-uart-image
program-arty-z7-uart-image:
	$(HOME)/Xilinx/2025.2/Vitis/bin/xsct scripts/zynq/program_and_run_uart_image.tcl
