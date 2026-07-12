# Continuous Integration

This repository uses two CI levels:

1. Hosted source checks on GitHub-hosted Ubuntu runners.
2. Vivado/XSim FPGA checks on a self-hosted runner with Xilinx tools installed.

The split is intentional. Open GitHub runners are good for source hygiene, but
Vivado, XSim, implementation, and Vitis builds require licensed FPGA tooling and
board-specific installation paths.

## Hosted CI

Workflow:

```text
.github/workflows/ci.yml
```

Checks:

- shell script syntax
- `shellcheck`
- Python syntax compilation
- Tcl syntax parsing
- Verilator lint through `make lint`

This workflow runs on pushes, pull requests, and manual dispatch.

## Vivado / XSim CI

Workflow:

```text
.github/workflows/vivado-xsim.yml
```

Runner requirements:

- Linux self-hosted GitHub Actions runner
- labels: `self-hosted`, `linux`, `vivado`
- Vivado 2025.2 available in `PATH`, or one of:
 - `VIVADO_SETTINGS=/path/to/Vivado/settings64.sh`
 - `$HOME/Xilinx/2025.2/Vivado/settings64.sh`
 - `/tools/Xilinx/2025.2/Vivado/settings64.sh`

Default checks:

```bash
make regression
make golden-test
make unit
```

The workflow uploads simulation logs as artifacts even on failure.

## Full FPGA Flow

The Vivado workflow has a manual `run_bitstream` option. When enabled, it runs:

```bash
make clean
make full-preboard-proof
```

This generates golden tensors and bare-metal headers, runs the model/golden/RTL
regression, creates the Arty Z7 Vivado project, builds the bitstream, exports the
XSA, builds the Vitis bare-metal application, and packages `build/BOOT.BIN`.

Use this full flow intentionally because it is much slower than RTL simulation.
