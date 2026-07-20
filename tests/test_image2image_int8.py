import random
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from models.image2image_int8 import (
    DEFAULT_DENOISE_QUANT_SHIFTS,
    LayerConfig,
    apply_residual,
    arithmetic_shift_right,
    conv2d_layer_int8,
    make_default_denoise_parameters,
    make_denoise_layer_configs,
    postprocess_accumulator,
    run_layers_int8,
    saturate_int8,
    tensor_shape_hwc,
)


def make_random_tensor(height, width, channels, rng, low=-8, high=8):
    return [
        [[rng.randint(low, high) for _ in range(channels)] for _ in range(width)]
        for _ in range(height)
    ]


def make_random_weights(cout, cin, kernel, rng, low=-3, high=3):
    return [
        [
            [[rng.randint(low, high) for _ in range(kernel)] for _ in range(kernel)]
            for _ in range(cin)
        ]
        for _ in range(cout)
    ]


class TestImage2ImageInt8Model(unittest.TestCase):
    def test_saturate_int8_edges(self):
        self.assertEqual(saturate_int8(127), 127)
        self.assertEqual(saturate_int8(128), 127)
        self.assertEqual(saturate_int8(-128), -128)
        self.assertEqual(saturate_int8(-129), -128)

    def test_arithmetic_shift_right(self):
        self.assertEqual(arithmetic_shift_right(7, 1), 3)
        self.assertEqual(arithmetic_shift_right(-3, 1), -2)
        self.assertEqual(arithmetic_shift_right(-5, 2), -2)

    def test_postprocess_order_relu_before_quantize(self):
        self.assertEqual(
            postprocess_accumulator(
                -3,
                0,
                bias_enable=True,
                relu_enable=True,
                quant_enable=True,
                quant_shift=1,
            ),
            0,
        )
        self.assertEqual(
            postprocess_accumulator(
                -3,
                0,
                bias_enable=True,
                relu_enable=False,
                quant_enable=True,
                quant_shift=1,
            ),
            -2,
        )

    def test_conv1x1_layer(self):
        x = [
            [[1, -2], [3, 4]],
            [[-5, 6], [7, -8]],
        ]
        weights = [[[[2]], [[-3]]]]
        bias = [1]
        cfg = LayerConfig(
            input_channels=2,
            output_channels=1,
            kernel_size=1,
            stride=1,
            padding=0,
            relu_enable=False,
            quant_enable=False,
        )

        y = conv2d_layer_int8(x, weights, bias, cfg)
        expected = [[[9], [-5]], [[-27], [39]]]
        self.assertEqual(y, expected)

    def test_conv3x3_padding_and_stride(self):
        flat = list(range(-12, 13))
        x = [[[flat[(y * 5) + x_idx]] for x_idx in range(5)] for y in range(5)]
        weights = [[[[1, 1, 1], [1, 1, 1], [1, 1, 1]]]]
        bias = [0]
        cfg = LayerConfig(
            input_channels=1,
            output_channels=1,
            kernel_size=3,
            stride=2,
            padding=1,
            relu_enable=False,
            quant_enable=False,
        )

        y = conv2d_layer_int8(x, weights, bias, cfg)
        expected = [
            [[-36], [-45], [-24]],
            [[-9], [0], [9]],
            [[24], [45], [36]],
        ]
        self.assertEqual(y, expected)

    def test_residual_subtract_saturates(self):
        base = [[[100, -100, 20]]]
        predicted_noise = [[[-40, 60, 100]]]

        y = apply_residual(base, predicted_noise, "sub")
        expected = [[[127, -128, -80]]]
        self.assertEqual(y, expected)

    def test_three_layer_denoise_network_shape(self):
        rng = random.Random(123)
        x = make_random_tensor(4, 5, 3, rng, -12, 12)
        configs = make_denoise_layer_configs(quant_shifts=(1, 1, 1), final_residual=True)
        layers = []

        for cfg in configs:
            weights = make_random_weights(
                cfg.output_channels,
                cfg.input_channels,
                cfg.kernel_size,
                rng,
            )
            bias = [rng.randint(-16, 16) for _ in range(cfg.output_channels)]
            layers.append((cfg, weights, bias))

        y = run_layers_int8(x, layers)
        self.assertEqual(tensor_shape_hwc(y), tensor_shape_hwc(x))

        for row in y:
            for pixel in row:
                for value in pixel:
                    self.assertGreaterEqual(value, -128)
                    self.assertLessEqual(value, 127)

    def test_default_denoiser_matches_gaussian_impulse_response(self):
        x = [[[0, 0, 0] for _ in range(5)] for _ in range(5)]
        x[2][2] = [64, 64, 64]

        configs = make_denoise_layer_configs(
            quant_shifts=DEFAULT_DENOISE_QUANT_SHIFTS,
            final_residual=True,
        )
        parameters = make_default_denoise_parameters()
        layers = [
            (cfg, weights, bias)
            for cfg, (weights, bias) in zip(configs, parameters)
        ]

        y = run_layers_int8(x, layers)
        expected_spatial = [
            [0, 0, 0, 0, 0],
            [0, 4, 8, 4, 0],
            [0, 8, 16, 8, 0],
            [0, 4, 8, 4, 0],
            [0, 0, 0, 0, 0],
        ]

        for row in range(5):
            for column in range(5):
                self.assertEqual(y[row][column], [expected_spatial[row][column]] * 3)

    def test_default_denoiser_uses_every_hidden_channel(self):
        parameters = make_default_denoise_parameters()
        layer0, _ = parameters[0]
        layer1, _ = parameters[1]
        layer2, _ = parameters[2]

        for output_channel in range(16):
            self.assertTrue(
                any(
                    layer0[output_channel][input_channel][ky][kx] != 0
                    for input_channel in range(3)
                    for ky in range(3)
                    for kx in range(3)
                )
            )
            self.assertTrue(
                any(
                    layer1[output_channel][input_channel][ky][kx] != 0
                    for input_channel in range(16)
                    for ky in range(3)
                    for kx in range(3)
                )
            )
            self.assertTrue(
                any(
                    layer1[next_output][output_channel][ky][kx] != 0
                    for next_output in range(16)
                    for ky in range(3)
                    for kx in range(3)
                )
            )
            self.assertTrue(
                any(
                    layer2[output_channel_rgb][output_channel][ky][kx] != 0
                    for output_channel_rgb in range(3)
                    for ky in range(3)
                    for kx in range(3)
                )
            )


if __name__ == "__main__":
    unittest.main()
