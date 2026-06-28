#!/usr/bin/env python3

NUM_INPUT_CHANNELS = 3
NUM_OUTPUT_CHANNELS = 4
KERNEL_TAPS = 9
WIDTH = 4
HEIGHT = 4

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

def make_weights():
    weights = [[[[0 for _ in range(3)] for _ in range(3)]
                for _ in range(NUM_INPUT_CHANNELS)]
                for _ in range(NUM_OUTPUT_CHANNELS)]

    # Center tap identity-like mapping.
    weights[0][0][1][1] = 1
    weights[1][1][1][1] = 1
    weights[2][2][1][1] = 1

    # Output channel 3 sums R + G + B center taps.
    weights[3][0][1][1] = 1
    weights[3][1][1][1] = 1
    weights[3][2][1][1] = 1

    return weights

def conv3x3_valid(image, weights, relu=True, bias=None):
    if bias is None:
        bias = [0] * NUM_OUTPUT_CHANNELS

    outputs = []

    for y in range(HEIGHT - 2):
        for x in range(WIDTH - 2):
            for oc in range(NUM_OUTPUT_CHANNELS):
                acc = bias[oc]

                for ic in range(NUM_INPUT_CHANNELS):
                    for ky in range(3):
                        for kx in range(3):
                            pixel = image[y + ky][x + kx][ic]
                            weight = weights[oc][ic][ky][kx]
                            acc += pixel * weight

                if relu and acc < 0:
                    acc = 0

                outputs.append(acc)

    return outputs

def main():
    image = make_image()
    weights = make_weights()
    outputs = conv3x3_valid(image, weights, relu=True)

    print("Golden CNN test")
    print(f"Image: {WIDTH}x{HEIGHT} RGB")
    print(f"Output words: {len(outputs)}")
    print()

    for i, value in enumerate(outputs):
        print(f"expected[{i:02d}] = {value}")

if __name__ == "__main__":
    main()
