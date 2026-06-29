#!/usr/bin/env python3

from pathlib import Path

WIDTH = 4
HEIGHT = 4
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

def make_input_image():
    words = []
    for y in range(HEIGHT):
        for x in range(WIDTH):
            r, g, b = pixel_rgb(x, y)
            words.append(packed_rgb(r, g, b))
    return words

def make_expected_output():
    outputs = []
    for y in range(HEIGHT - 2):
        for x in range(WIDTH - 2):
            cx = x + 1
            cy = y + 1
            r, g, b = pixel_rgb(cx, cy)

            outputs.append(r)
            outputs.append(g)
            outputs.append(b)
            outputs.append(r + g + b)

    return outputs

def write_test_image_h(words):
    path = OUT_DIR / "test_image.h"

    with path.open("w") as f:
        f.write("#ifndef TEST_IMAGE_H\n")
        f.write("#define TEST_IMAGE_H\n\n")
        f.write("#include <stdint.h>\n\n")
        f.write(f"#define IMAGE_WIDTH {WIDTH}U\n")
        f.write(f"#define IMAGE_HEIGHT {HEIGHT}U\n")
        f.write(f"#define IMAGE_PIXELS {len(words)}U\n\n")
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
    image = make_input_image()
    expected = make_expected_output()

    write_test_image_h(image)
    write_expected_output_h(expected)

    print("Generated:")
    print("  software/zynq_baremetal/generated/test_image.h")
    print("  software/zynq_baremetal/generated/expected_output.h")
    print(f"Image: {WIDTH}x{HEIGHT}")
    print(f"Input pixels: {len(image)}")
    print(f"Expected output words: {len(expected)}")

if __name__ == "__main__":
    main()
