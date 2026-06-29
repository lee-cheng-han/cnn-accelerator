#!/usr/bin/env python3

from pathlib import Path
import argparse

NUM_OUTPUT_CHANNELS = 4

OUT_DIR = Path("software/zynq_baremetal/generated")
OUT_DIR.mkdir(parents=True, exist_ok=True)

def pixel_rgb(x, y):
    r = x + 1
    g = y + 1
    b = x + y + 1
    return r, g, b

def packed_rgb(r, g, b):
    return (b << 16) | (g << 8) | r

def make_input_image(width, height):
    words = []
    for y in range(height):
        for x in range(width):
            r, g, b = pixel_rgb(x, y)
            words.append(packed_rgb(r, g, b))
    return words

def make_expected_output(width, height, kernel):
    outputs = []

    if kernel == "3x3":
        for y in range(height - 2):
            for x in range(width - 2):
                cx = x + 1
                cy = y + 1
                r, g, b = pixel_rgb(cx, cy)

                outputs.append(r)
                outputs.append(g)
                outputs.append(b)
                outputs.append(r + g + b)

    elif kernel == "1x1":
        for y in range(height):
            for x in range(width):
                r, g, b = pixel_rgb(x, y)

                outputs.append(r)
                outputs.append(g)
                outputs.append(b)
                outputs.append(r + g + b)

    else:
        raise ValueError(f"Unsupported kernel: {kernel}")

    return outputs

def write_test_image_h(words, width, height, kernel):
    path = OUT_DIR / "test_image.h"

    with path.open("w") as f:
        f.write("#ifndef TEST_IMAGE_H\n")
        f.write("#define TEST_IMAGE_H\n\n")
        f.write("#include <stdint.h>\n\n")
        f.write(f"#define IMAGE_WIDTH {width}U\n")
        f.write(f"#define IMAGE_HEIGHT {height}U\n")
        f.write(f"#define IMAGE_PIXELS {len(words)}U\n")
        f.write(f"#define TEST_KERNEL_MODE {1 if kernel == "3x3" else 0}U\n")
        f.write(f"#define TEST_KERNEL_NAME \"{kernel}\"\n\n")
        f.write("static const uint32_t input_image[IMAGE_PIXELS] = {\n")

        for i, word in enumerate(words):
            comma = "," if i + 1 < len(words) else ""
            f.write(f"    0x{word:08x}U{comma}\n")

        f.write("};\n\n")
        f.write("#endif\n")

def write_expected_output_h(outputs):
    path = OUT_DIR / "expected_output.h"

    with path.open("w") as f:
        f.write("#ifndef EXPECTED_OUTPUT_H\n")
        f.write("#define EXPECTED_OUTPUT_H\n\n")
        f.write("#include <stdint.h>\n\n")
        f.write(f"#define EXPECTED_OUTPUT_WORDS {len(outputs)}U\n\n")
        f.write("static const int32_t expected_output[EXPECTED_OUTPUT_WORDS] = {\n")

        for i, value in enumerate(outputs):
            comma = "," if i + 1 < len(outputs) else ""
            f.write(f"    {value}{comma}\n")

        f.write("};\n\n")
        f.write("#endif\n")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--width", type=int, default=4)
    parser.add_argument("--height", type=int, default=4)
    parser.add_argument("--kernel", choices=["1x1", "3x3"], default="3x3")
    args = parser.parse_args()

    if args.kernel == "3x3" and (args.width < 3 or args.height < 3):
        raise SystemExit("Width and height must be at least 3 for a 3x3 valid convolution.")

    if args.kernel == "1x1" and (args.width < 1 or args.height < 1):
        raise SystemExit("Width and height must be at least 1 for a 1x1 convolution.")

    image = make_input_image(args.width, args.height)
    expected = make_expected_output(args.width, args.height, args.kernel)

    write_test_image_h(image, args.width, args.height, args.kernel)
    write_expected_output_h(expected)

    print("Generated:")
    print("  software/zynq_baremetal/generated/test_image.h")
    print("  software/zynq_baremetal/generated/expected_output.h")
    print(f"Image: {args.width}x{args.height}")
    print(f"Kernel: {args.kernel}")
    print(f"Input pixels: {len(image)}")
    print(f"Expected output words: {len(expected)}")

if __name__ == "__main__":
    main()
