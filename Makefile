SHELL := /bin/bash

TB ?= tb_cnn_accel_top_small
SEED ?= 12345

.PHONY: xsim regression xsim-regression lint vectors synth clean

xsim:
	SEED=$(SEED) bash scripts/run_xsim_tb.sh $(TB)

regression:
	SEED=$(SEED) bash scripts/run_xsim_regression.sh

xsim-regression:
	SEED=$(SEED) bash scripts/run_xsim_regression.sh

lint:
	bash scripts/lint_verilator.sh

vectors:
	python3 models/generate_vectors.py

synth:
	vivado -mode batch -source scripts/synth_vivado.tcl

clean:
	rm -rf sim .Xil
	rm -f *.jou *.log *.pb *.vcd

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
	~/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/zynq/synth_axi_system_zynq.tcl

.PHONY: arty-z7-project

arty-z7-project:
	~/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/zynq/create_arty_z7_20_project.tcl

.PHONY: arty-z7-bitstream

arty-z7-bitstream:
	~/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/zynq/build_arty_z7_20_bitstream.tcl

.PHONY: arty-z7-xsa

arty-z7-xsa:
	~/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/zynq/export_arty_z7_20_xsa.tcl

.PHONY: vitis-app clean-vitis clean-generated full-arty-z7-flow

vitis-app:
	rm -rf build/vitis_ws
	~/Xilinx/2025.2/Vitis/bin/vitis -source scripts/vitis/create_zynq_baremetal_app.py

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

.PHONY: arty-z7-bitstream
arty-z7-bitstream:
	$(HOME)/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/zynq/build_arty_z7_20_bitstream.tcl

.PHONY: arty-z7-xsa
arty-z7-xsa:
	$(HOME)/Xilinx/2025.2/Vivado/bin/vivado -mode batch -source scripts/zynq/export_arty_z7_20_xsa.tcl

.PHONY: vitis-dma-app
vitis-dma-app:
	$(HOME)/Xilinx/2025.2/Vitis/bin/vitis -s scripts/vitis/create_zynq_baremetal_app.py

.PHONY: full-arty-z7-dma-flow
full-arty-z7-dma-flow:
	python3 scripts/image/generate_test_headers.py --width 8 --height 8 --kernel 3x3
	$(MAKE) dma-sim
	$(MAKE) arty-z7-project
	$(MAKE) arty-z7-bitstream
	$(MAKE) arty-z7-xsa
	$(MAKE) vitis-dma-app

.PHONY: program-arty-z7-dma
program-arty-z7-dma:
	$(HOME)/Xilinx/2025.2/Vitis/bin/xsct scripts/zynq/program_and_run_dma.tcl

