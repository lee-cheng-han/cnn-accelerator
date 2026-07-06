#!/usr/bin/env bash
set -euo pipefail

BOOTGEN="${BOOTGEN:-$HOME/Xilinx/2025.2/Vitis/bin/bootgen}"
FSBL="build/vitis_ws/arty_z7_20_cnn_platform/zynq_fsbl/build/fsbl.elf"
BIT="build/arty_z7_20_cnn/arty_z7_20_cnn.runs/impl_1/system_wrapper.bit"
ELF="build/vitis_ws/cnn_baremetal/build/cnn_baremetal.elf"
BIF="build/boot_image.bif"
OUT="build/BOOT.BIN"

for path in "$BOOTGEN" "$FSBL" "$BIT" "$ELF"; do
  if [[ ! -e "$path" ]]; then
    echo "Missing required file: $path" >&2
    echo "Run: make full-arty-z7-dma-flow" >&2
    exit 1
  fi
done

mkdir -p build

cat > "$BIF" <<BIF
the_ROM_image:
{
  [bootloader] $FSBL
  $BIT
  $ELF
}
BIF

"$BOOTGEN" -arch zynq -image "$BIF" -o "$OUT" -w

echo "BOOT image created:"
echo "  $OUT"
echo "BIF:"
echo "  $BIF"
