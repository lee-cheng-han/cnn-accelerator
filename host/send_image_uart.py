#!/usr/bin/env python3

import argparse
import struct
import sys
import time

try:
    import serial
except ImportError:
    print("Missing dependency: pyserial")
    print("Install with: pip install pyserial")
    sys.exit(1)

NUM_INPUT_CHANNELS = 3
NUM_OUTPUT_CHANNELS = 4
KERNEL_TAPS = 9

def int8_to_byte(value):
    if value < -128 or value > 127:
        raise ValueError(f"INT8 out of range: {value}")
    return value & 0xFF

def byte_to_int8(value):
    value &= 0xFF
    return value - 256 if value >= 128 else value

def clamp_int8(value):
    return max(-128, min(127, value))

def build_demo_image(width, height):
    image = []
    for y in range(height):
        for x in range(width):
            ch0 = x + 1
            ch1 = y + 1
            ch2 = x + y + 1
            image.extend([clamp_int8(ch0), clamp_int8(ch1), clamp_int8(ch2)])
    return image

def build_demo_weights():
    weights = [0] * (NUM_OUTPUT_CHANNELS * NUM_INPUT_CHANNELS * KERNEL_TAPS)

    def idx(oc, ic, tap):
        return oc * NUM_INPUT_CHANNELS * KERNEL_TAPS + ic * KERNEL_TAPS + tap

    weights[idx(0, 0, 0)] = 1
    weights[idx(1, 1, 0)] = 1
    weights[idx(2, 2, 0)] = 1
    weights[idx(3, 0, 0)] = 1
    weights[idx(3, 1, 0)] = 1
    weights[idx(3, 2, 0)] = 1

    return weights

def compute_expected(image, width, height):
    expected = []
    for pix in range(width * height):
        base = pix * 3
        ch0 = image[base + 0]
        ch1 = image[base + 1]
        ch2 = image[base + 2]
        expected.extend([
            clamp_int8(ch0),
            clamp_int8(ch1),
            clamp_int8(ch2),
            clamp_int8(ch0 + ch1 + ch2),
        ])
    return expected

def send_config(ser, width, height):
    mode = 0
    flags = 0
    quant_shift = 0

    packet = bytearray()
    packet.extend(b"C")
    packet.extend(struct.pack("<H", width))
    packet.extend(struct.pack("<H", height))
    packet.append(mode)
    packet.append(flags)
    packet.append(quant_shift)
    ser.write(packet)

def send_weights(ser, weights):
    packet = bytearray(b"W")
    packet.extend(int8_to_byte(w) for w in weights)
    ser.write(packet)

def send_bias(ser):
    packet = bytearray(b"B")
    for _ in range(4):
        packet.extend(struct.pack("<i", 0))
    ser.write(packet)

def send_image(ser, image):
    packet = bytearray(b"I")
    packet.extend(struct.pack("<I", len(image)))
    packet.extend(int8_to_byte(v) for v in image)
    ser.write(packet)

def request_results(ser, expected_len, timeout_s):
    ser.write(b"R")

    data = bytearray()
    deadline = time.time() + timeout_s

    while len(data) < expected_len and time.time() < deadline:
        chunk = ser.read(expected_len - len(data))
        if chunk:
            data.extend(chunk)

    return bytes(data)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--width", type=int, default=4)
    parser.add_argument("--height", type=int, default=4)
    parser.add_argument("--timeout", type=float, default=5.0)
    args = parser.parse_args()

    image = build_demo_image(args.width, args.height)
    weights = build_demo_weights()
    expected = compute_expected(image, args.width, args.height)

    print(f"Opening {args.port} at {args.baud} baud")

    with serial.Serial(args.port, args.baud, timeout=0.1) as ser:
        time.sleep(0.2)
        ser.reset_input_buffer()
        ser.reset_output_buffer()

        print("Sending config")
        send_config(ser, args.width, args.height)

        print("Sending weights")
        send_weights(ser, weights)

        print("Sending bias")
        send_bias(ser)

        print(f"Sending image: {len(image)} bytes")
        send_image(ser, image)

        time.sleep(0.1)

        print(f"Requesting {len(expected)} result bytes")
        received = request_results(ser, len(expected), args.timeout)

    print(f"Received {len(received)} bytes")

    if len(received) != len(expected):
        print(f"FAIL: expected {len(expected)} bytes, got {len(received)}")
        return 1

    received_signed = [byte_to_int8(b) for b in received]

    errors = 0
    for i, (got, exp) in enumerate(zip(received_signed, expected)):
        if got != exp:
            print(f"Mismatch index {i}: got {got}, expected {exp}")
            errors += 1
            if errors >= 20:
                break

    if errors:
        print(f"FAIL: {errors} mismatches")
        return 1

    print("PASS: received data matches expected output")
    print("First output bytes:")
    print(received_signed[:32])
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
