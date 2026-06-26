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
