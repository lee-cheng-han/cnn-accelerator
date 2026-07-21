import json
from pathlib import Path
import random
import tempfile
import unittest

from models.cnn_abi import parse_model_package
from models.image2image_int8 import (
    DEFAULT_DENOISE_QUANT_SHIFTS,
    LayerConfig,
    make_default_denoise_parameters,
    make_denoise_layer_configs,
    run_layers_int8,
)
from models.model_compiler import CompilerError, compile_model, package_summary
from models.package_executor import execute_model_package


def random_tensor(height, width, channels, seed=11):
    rng = random.Random(seed)
    return [
        [[rng.randint(-8, 8) for _ in range(channels)] for _ in range(width)]
        for _ in range(height)
    ]


def random_weights(cout, cin, kernel, rng):
    return [
        [
            [[rng.randint(-3, 3) for _ in range(kernel)] for _ in range(kernel)]
            for _ in range(cin)
        ]
        for _ in range(cout)
    ]


def mixed_model_spec():
    rng = random.Random(22)
    layer0_weights = random_weights(4, 3, 1, rng)
    layer1_weights = random_weights(2, 4, 3, rng)
    return {
        "format": "cnn-accelerator-model-v1",
        "model_id": 100,
        "model_generation_id": 3,
        "input": {"name": "rgb", "width": 5, "height": 4, "channels": 3},
        "layers": [
            {
                "name": "color_projection",
                "output": "features",
                "output_channels": 4,
                "kernel_size": 1,
                "padding": 0,
                "activation": "relu",
                "quant_shift": 1,
                "weights": layer0_weights,
                "bias": [2, -1, 3, 0],
            },
            {
                "name": "spatial_filter",
                "output": "filtered",
                "output_channels": 2,
                "kernel_size": 3,
                "padding": 1,
                "activation": "none",
                "quant_shift": 2,
                "weights": layer1_weights,
                "bias": [-4, 5],
            },
        ],
    }, layer0_weights, layer1_weights


class TestModelCompiler(unittest.TestCase):
    def test_mixed_network_matches_existing_bit_accurate_model(self):
        spec, layer0_weights, layer1_weights = mixed_model_spec()
        package = compile_model(spec)
        input_tensor = random_tensor(4, 5, 3)
        actual = execute_model_package(package, input_tensor)
        expected = run_layers_int8(
            input_tensor,
            [
                (
                    LayerConfig(3, 4, kernel_size=1, padding=0, relu_enable=True,
                                quant_shift=1),
                    layer0_weights,
                    [2, -1, 3, 0],
                ),
                (
                    LayerConfig(4, 2, kernel_size=3, padding=1, relu_enable=False,
                                quant_shift=2),
                    layer1_weights,
                    [-4, 5],
                ),
            ],
        )
        self.assertEqual(actual, expected)

    def test_default_gaussian_network_round_trips_through_package(self):
        configs = make_denoise_layer_configs(
            quant_shifts=DEFAULT_DENOISE_QUANT_SHIFTS,
            final_residual=True,
        )
        parameters = make_default_denoise_parameters()
        layers = []
        for index, (cfg, (weights, bias)) in enumerate(zip(configs, parameters)):
            layers.append(
                {
                    "name": f"gaussian_{index}",
                    "output": "output" if index == 2 else f"hidden_{index}",
                    "output_channels": cfg.output_channels,
                    "kernel_size": cfg.kernel_size,
                    "stride": cfg.stride,
                    "padding": cfg.padding,
                    "activation": "relu" if cfg.relu_enable else "none",
                    "quant_shift": cfg.quant_shift,
                    "weights": weights,
                    "bias": bias,
                    **(
                        {"residual": "input", "residual_mode": "subtract"}
                        if index == 2 else {}
                    ),
                }
            )
        spec = {
            "format": "cnn-accelerator-model-v1",
            "model_id": 101,
            "input": {"width": 5, "height": 5, "channels": 3},
            "layers": layers,
        }
        input_tensor = [[[0, 0, 0] for _ in range(5)] for _ in range(5)]
        input_tensor[2][2] = [64, 64, 64]
        package = compile_model(spec)
        actual = execute_model_package(package, input_tensor)
        expected = run_layers_int8(
            input_tensor,
            [
                (config, weights, bias)
                for config, (weights, bias) in zip(configs, parameters)
            ],
        )
        self.assertEqual(actual, expected)

    def test_asymmetric_padding_is_descriptor_driven(self):
        spec = {
            "format": "cnn-accelerator-model-v1",
            "model_id": 102,
            "input": {"width": 3, "height": 2, "channels": 1},
            "layers": [
                {
                    "output_channels": 1,
                    "kernel_size": 3,
                    "padding": [1, 0, 1, 0],
                    "weights": [[[[1, 1, 1], [1, 1, 1], [1, 1, 1]]]],
                    "bias": [0],
                }
            ],
        }
        package = compile_model(spec)
        output = execute_model_package(package, [[[1], [2], [3]], [[4], [5], [6]]])
        self.assertEqual(output, [[[12], [21]]])

    def test_compilation_is_deterministic_and_reports_layout(self):
        spec, _, _ = mixed_model_spec()
        first = compile_model(spec)
        second = compile_model(spec)
        self.assertEqual(first, second)
        summary = package_summary(first)
        self.assertEqual(summary["layer_count"], 2)
        self.assertEqual(summary["layers"][0]["kernel"], [1, 1])
        self.assertEqual(summary["layers"][1]["kernel"], [3, 3])

    def test_workspace_allocator_reuses_dead_input_storage(self):
        spec, _, _ = mixed_model_spec()
        header, _, tensors, _ = parse_model_package(compile_model(spec))
        self.assertEqual(tensors[0].ddr_offset, tensors[2].ddr_offset)
        unoptimized_size = sum(
            ((tensor.allocation_size + 63) // 64) * 64 for tensor in tensors
        )
        self.assertLess(header.workspace_size, unoptimized_size)

    def test_raw_parameter_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "weights.bin").write_bytes(bytes([2, 0xFD]))
            (root / "bias.json").write_text(json.dumps([1]), encoding="utf-8")
            spec = {
                "format": "cnn-accelerator-model-v1",
                "model_id": 103,
                "input": {"width": 1, "height": 1, "channels": 2},
                "layers": [
                    {
                        "output_channels": 1,
                        "kernel_size": 1,
                        "weights_file": "weights.bin",
                        "bias_file": "bias.json",
                    }
                ],
            }
            package = compile_model(spec, base_dir=root)
            self.assertEqual(execute_model_package(package, [[[4, 5]]]), [[[-6]]])

    def test_rejects_wrong_weight_shape(self):
        spec, _, _ = mixed_model_spec()
        spec["layers"][0]["weights"] = [1, 2]
        with self.assertRaisesRegex(CompilerError, "weights requires 12 values"):
            compile_model(spec)

    def test_rejects_invalid_stride_with_compiler_diagnostic(self):
        spec, _, _ = mixed_model_spec()
        spec["layers"][0]["stride"] = 0
        with self.assertRaisesRegex(CompilerError, "stride values must be 1 or 2"):
            compile_model(spec)

    def test_rejects_non_boolean_bias_enable(self):
        spec, _, _ = mixed_model_spec()
        spec["layers"][0]["bias_enable"] = "false"
        with self.assertRaisesRegex(CompilerError, "must be true or false"):
            compile_model(spec)

    def test_rejects_incompatible_residual_shape(self):
        spec, _, _ = mixed_model_spec()
        spec["layers"][1].update(
            {"residual": "rgb", "residual_mode": "add", "quantization_profile": "input"}
        )
        with self.assertRaisesRegex(ValueError, "residual tensor shape"):
            compile_model(spec)


if __name__ == "__main__":
    unittest.main()
