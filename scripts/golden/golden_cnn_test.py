#!/usr/bin/env python3

WIDTH = 4
HEIGHT = 4
NUM_INPUT_CHANNELS = 3
NUM_OUTPUT_CHANNELS = 4

def make_image():
    image = []
    for y in range(HEIGHT):
        row = []
        for x in range(WIDTH):
            r = x + 1
            g = y + 1
            b = x + y + 1
            row.append([r, g, b])
        image.append(row)
    return image

def expected_outputs():
    image = make_image()
    outputs = []

    # Valid 3x3 output positions for 4x4 input = 2x2 windows.
    # Center tap identity-like weights:
    # oc0 = R center
    # oc1 = G center
    # oc2 = B center
    # oc3 = R + G + B center
    for y in range(HEIGHT - 2):
        for x in range(WIDTH - 2):
            center = image[y + 1][x + 1]
            r, g, b = center

            outputs.append(r)
            outputs.append(g)
            outputs.append(b)
            outputs.append(r + g + b)

    return outputs

def main():
    outputs = expected_outputs()

    print("Golden CNN test")
    print(f"Input image: {WIDTH}x{HEIGHT} RGB")
    print(f"Output words: {len(outputs)}")
    print()

    for i, value in enumerate(outputs):
        print(f"expected[{i:02d}] = {value}")

if __name__ == "__main__":
    main()
