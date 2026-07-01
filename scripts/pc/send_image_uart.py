#!/usr/bin/env python3
"""
Send an image to the Zynq CNN accelerator over UART and receive the output.

Protocol:
PC -> Board:
  magic        4 bytes: b"CNNI"
  width        uint32 little-endian
  height       uint32 little-endian
  kernel_mode  uint32 little-endian, 0=1x1, 1=3x3
  pixel_count  uint32 little-endian
  pixels       pixel_count uint32 words, packed as 0x00BBGGRR

Board -> PC:
  magic           4 bytes: b"CNNO"
  output_width    uint32 little-endian
  output_height   uint32 little-endian
  output_channels uint32 little-endian
  output_words    uint32 little-endian
  output_data     output_words int32 words
"""

from __future__ import annotations

import argparse
import struct
import sys
import time
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow is required. Install with: python3 -m pip install pillow", file=sys.stderr)
    raise

try:
    import serial
except ImportError:
    print("ERROR: pyserial is required. Install with: python3 -m pip install pyserial", file=sys.stderr)
    raise


MAX_WIDTH = 64
MAX_HEIGHT = 64
INPUT_MAGIC = b"CNNI"
OUTPUT_MAGIC = b"CNNO"


def kernel_to_mode(kernel: str) -> int:
    if kernel == "1x1":
        return 0
    if kernel == "3x3":
        return 1
    raise ValueError(f"Unsupported kernel: {kernel}")


def expected_output_shape(width: int, height: int, kernel_mode: int) -> tuple[int, int]:
    if kernel_mode == 0:
        return width, height

    if width < 3 or height < 3:
        raise ValueError("3x3 mode requires width and height >= 3")

    return width - 2, height - 2


def load_image_as_packed_rgb(path: Path, width: int, height: int) -> list[int]:
    img = Image.open(path).convert("RGB")
    img = img.resize((width, height), Image.Resampling.BILINEAR)

    packed: list[int] = []

    for r, g, b in img.getdata():
        word = (b << 16) | (g << 8) | r
        packed.append(word)

    return packed


def build_input_packet(width: int, height: int, kernel_mode: int, pixels: list[int]) -> bytes:
    header = INPUT_MAGIC
    header += struct.pack("<IIII", width, height, kernel_mode, len(pixels))

    payload = bytearray()
    for p in pixels:
        payload += struct.pack("<I", p)

    return header + payload


def read_exact(ser: serial.Serial, nbytes: int, timeout_s: float) -> bytes:
    deadline = time.time() + timeout_s
    data = bytearray()

    while len(data) < nbytes:
        if time.time() > deadline:
            raise TimeoutError(f"Timed out reading {nbytes} bytes; got {len(data)} bytes")

        chunk = ser.read(nbytes - len(data))
        if chunk:
            data.extend(chunk)

    return bytes(data)


def receive_output_packet(ser: serial.Serial, timeout_s: float) -> tuple[int, int, int, list[int]]:
    magic = read_exact(ser, 4, timeout_s)
    if magic != OUTPUT_MAGIC:
        raise RuntimeError(f"Bad output magic: expected {OUTPUT_MAGIC!r}, got {magic!r}")

    header = read_exact(ser, 16, timeout_s)
    out_w, out_h, out_ch, out_words = struct.unpack("<IIII", header)

    if out_ch != 4:
        raise RuntimeError(f"Expected 4 output channels, got {out_ch}")

    payload_bytes = out_words * 4
    payload = read_exact(ser, payload_bytes, timeout_s)

    values = list(struct.unpack(f"<{out_words}i", payload))
    return out_w, out_h, out_ch, values


def clamp_u8(x: int) -> int:
    if x < 0:
        return 0
    if x > 255:
        return 255
    return x


def save_output_preview(
    output_path: Path,
    out_w: int,
    out_h: int,
    out_ch: int,
    values: list[int],
) -> None:
    expected = out_w * out_h * out_ch
    if len(values) != expected:
        raise RuntimeError(f"Output word count mismatch: expected {expected}, got {len(values)}")

    pixels: list[tuple[int, int, int]] = []

    for i in range(out_w * out_h):
        base = i * out_ch
        r = clamp_u8(values[base + 0])
        g = clamp_u8(values[base + 1])
        b = clamp_u8(values[base + 2])
        pixels.append((r, g, b))

    img = Image.new("RGB", (out_w, out_h))
    img.putdata(pixels)
    img.save(output_path)


def save_raw_output(path: Path, values: list[int]) -> None:
    with path.open("wb") as f:
        for v in values:
            f.write(struct.pack("<i", v))


def main() -> int:
    parser = argparse.ArgumentParser(description="Send image to Zynq CNN accelerator over UART")
    parser.add_argument("image", type=Path, help="Input image path, e.g. input.png")
    parser.add_argument("--port", required=True, help="Serial port, e.g. COM5, /dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=115200, help="UART baud rate")
    parser.add_argument("--width", type=int, default=32, help="Resize width, max 64 for current RTL")
    parser.add_argument("--height", type=int, default=32, help="Resize height, max 64 for current RTL")
    parser.add_argument("--kernel", choices=["1x1", "3x3"], default="3x3")
    parser.add_argument("--out", type=Path, default=Path("output.png"), help="Output preview PNG")
    parser.add_argument("--raw-out", type=Path, default=Path("output_words.bin"), help="Raw int32 output words")
    parser.add_argument("--timeout", type=float, default=30.0, help="UART read timeout in seconds")
    parser.add_argument("--dry-run", action="store_true", help="Build packet and print info without using UART")

    args = parser.parse_args()

    if args.width <= 0 or args.height <= 0:
        raise ValueError("Width and height must be positive")

    if args.width > MAX_WIDTH or args.height > MAX_HEIGHT:
        raise ValueError(f"Current RTL supports max {MAX_WIDTH}x{MAX_HEIGHT}")

    kernel_mode = kernel_to_mode(args.kernel)
    out_w, out_h = expected_output_shape(args.width, args.height, kernel_mode)

    pixels = load_image_as_packed_rgb(args.image, args.width, args.height)
    packet = build_input_packet(args.width, args.height, kernel_mode, pixels)

    expected_output_words = out_w * out_h * 4

    print("Input image:", args.image)
    print("UART port:", args.port)
    print("Baud:", args.baud)
    print("Kernel:", args.kernel)
    print("Input size:", f"{args.width}x{args.height}")
    print("Input pixels:", len(pixels))
    print("Input packet bytes:", len(packet))
    print("Expected output size:", f"{out_w}x{out_h}")
    print("Expected output words:", expected_output_words)
    print("Expected output bytes:", expected_output_words * 4)

    if args.dry_run:
        print("Dry run only. Not sending UART packet.")
        return 0

    with serial.Serial(args.port, args.baud, timeout=0.1) as ser:
        # Give board time if serial port reset behavior occurs.
        time.sleep(0.2)
        ser.reset_input_buffer()
        ser.reset_output_buffer()

        print("Sending packet...")
        ser.write(packet)
        ser.flush()

        print("Waiting for output packet...")
        out_w_rx, out_h_rx, out_ch_rx, values = receive_output_packet(ser, args.timeout)

    print("Received output:")
    print("  width:", out_w_rx)
    print("  height:", out_h_rx)
    print("  channels:", out_ch_rx)
    print("  words:", len(values))

    save_raw_output(args.raw_out, values)
    save_output_preview(args.out, out_w_rx, out_h_rx, out_ch_rx, values)

    print("Saved raw output:", args.raw_out)
    print("Saved preview image:", args.out)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
