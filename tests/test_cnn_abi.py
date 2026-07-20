import dataclasses
from pathlib import Path
import re
import struct
import unittest

from models.cnn_abi import (
    ABI_VERSION,
    LAYER_DESCRIPTOR_SIZE,
    MODEL_HEADER_SIZE,
    QUANT_DESCRIPTOR_SIZE,
    TENSOR_DESCRIPTOR_SIZE,
    AbiError,
    Activation,
    LayerDescriptor,
    LayerFlags,
    ModelHeader,
    QuantizationDescriptor,
    ResidualMode,
    TensorDescriptor,
    TensorFlags,
    compute_package_crc32,
    compute_package_sha256,
    parse_model_package,
    parameter_crc32,
    validate_model,
)


def valid_model():
    tensors = [
        TensorDescriptor(0, 0, 48, 4, 4, 3, 0, 0, 1, 12, 3,
                         flags=TensorFlags.MODEL_INPUT),
        TensorDescriptor(1, 64, 48, 4, 4, 3, 0, 1, 1, 12, 3,
                         flags=TensorFlags.MODEL_OUTPUT),
    ]
    quant = [QuantizationDescriptor(0, quant_shift=4)]
    layers = [
        LayerDescriptor(
            layer_id=0, input_tensor_id=0, output_tensor_id=1,
            quantization_id=0, weight_offset=512, weight_size=81,
            bias_offset=596, bias_size=12, parameter_crc32=0x12345678,
            kernel_height=3, kernel_width=3, stride_y=1, stride_x=1,
            padding_top=1, padding_bottom=1, padding_left=1, padding_right=1,
            activation=Activation.RELU, flags=LayerFlags.BIAS_ENABLE | LayerFlags.LAST_LAYER,
        )
    ]
    header = ModelHeader(
        package_size=640, model_id=7, model_generation_id=9,
        layer_count=1, tensor_count=2, quantization_count=1,
        layer_table_offset=128, tensor_table_offset=256,
        quantization_table_offset=384, parameter_data_offset=512,
        parameter_data_size=128, input_tensor_id=0, output_tensor_id=1,
        workspace_size=128,
    )
    return header, layers, tensors, quant


def encoded_valid_package():
    header, layers, tensors, quant = valid_model()
    weight_bytes = bytes(range(81))
    bias_bytes = bytes(range(12))
    layers[0] = dataclasses.replace(
        layers[0], parameter_crc32=parameter_crc32(weight_bytes, bias_bytes)
    )
    package = bytearray(header.package_size)
    package[:MODEL_HEADER_SIZE] = header.pack()
    package[header.layer_table_offset:header.layer_table_offset + LAYER_DESCRIPTOR_SIZE] = layers[0].pack()
    for index, tensor in enumerate(tensors):
        start = header.tensor_table_offset + index * TENSOR_DESCRIPTOR_SIZE
        package[start:start + TENSOR_DESCRIPTOR_SIZE] = tensor.pack()
    package[header.quantization_table_offset:header.quantization_table_offset
            + QUANT_DESCRIPTOR_SIZE] = quant[0].pack()
    package[512:593] = weight_bytes
    package[596:608] = bias_bytes
    header = dataclasses.replace(header, package_sha256=compute_package_sha256(package))
    package[:MODEL_HEADER_SIZE] = header.pack()
    header = dataclasses.replace(header, package_crc32=compute_package_crc32(package))
    package[:MODEL_HEADER_SIZE] = header.pack()
    return bytes(package)


class TestCnnAbi(unittest.TestCase):
    def test_record_sizes_and_round_trips(self):
        header, layers, tensors, quant = valid_model()
        records = (
            (header, ModelHeader, MODEL_HEADER_SIZE),
            (layers[0], LayerDescriptor, LAYER_DESCRIPTOR_SIZE),
            (tensors[0], TensorDescriptor, TENSOR_DESCRIPTOR_SIZE),
            (quant[0], QuantizationDescriptor, QUANT_DESCRIPTOR_SIZE),
        )
        for record, record_type, expected_size in records:
            encoded = record.pack()
            self.assertEqual(len(encoded), expected_size)
            self.assertEqual(record_type.unpack(encoded), record)

    def test_binary_is_little_endian_and_versioned(self):
        header, layers, _, _ = valid_model()
        encoded = header.pack()
        self.assertEqual(encoded[:4], b"CNN1")
        self.assertEqual(struct.unpack_from("<H", encoded, 4)[0], ABI_VERSION)
        self.assertEqual(struct.unpack_from("<I", layers[0].pack(), 20)[0], 512)

    def test_reserved_bytes_are_rejected(self):
        _, layers, _, _ = valid_model()
        encoded = bytearray(layers[0].pack())
        encoded[127] = 1
        with self.assertRaisesRegex(AbiError, "reserved bytes"):
            LayerDescriptor.unpack(bytes(encoded))

    def test_unknown_flags_are_rejected(self):
        _, layers, _, _ = valid_model()
        encoded = bytearray(layers[0].pack())
        struct.pack_into("<I", encoded, 8, 0x80000000)
        with self.assertRaisesRegex(AbiError, "unknown layer flags"):
            LayerDescriptor.unpack(bytes(encoded))

    def test_parameter_crc_covers_weights_then_biases(self):
        self.assertEqual(parameter_crc32(b"weights", b"bias"), 0x54E5C5F8)
        self.assertNotEqual(parameter_crc32(b"bias", b"weights"), 0x54E5C5F8)

    def test_c_and_systemverilog_constants_match_python(self):
        root = Path(__file__).resolve().parents[1]
        c_header = (root / "software/zynq_baremetal/cnn_accel_abi.h").read_text()
        sv_package = (root / "rtl/include/cnn_accel_abi_pkg.sv").read_text()
        expected = {
            "ABI_VERSION": ABI_VERSION,
            "MODEL_HEADER_SIZE": MODEL_HEADER_SIZE,
            "LAYER_DESCRIPTOR_SIZE": LAYER_DESCRIPTOR_SIZE,
            "TENSOR_DESCRIPTOR_SIZE": TENSOR_DESCRIPTOR_SIZE,
            "QUANT_DESCRIPTOR_SIZE": QUANT_DESCRIPTOR_SIZE,
        }
        c_names = {
            "ABI_VERSION": "CNN_ABI_VERSION",
            "MODEL_HEADER_SIZE": "CNN_MODEL_HEADER_SIZE",
            "LAYER_DESCRIPTOR_SIZE": "CNN_LAYER_DESCRIPTOR_SIZE",
            "TENSOR_DESCRIPTOR_SIZE": "CNN_TENSOR_DESCRIPTOR_SIZE",
            "QUANT_DESCRIPTOR_SIZE": "CNN_QUANT_DESCRIPTOR_SIZE",
        }
        sv_names = {
            "ABI_VERSION": "ABI_VERSION",
            "MODEL_HEADER_SIZE": "MODEL_HEADER_BYTES",
            "LAYER_DESCRIPTOR_SIZE": "LAYER_DESCRIPTOR_BYTES",
            "TENSOR_DESCRIPTOR_SIZE": "TENSOR_DESCRIPTOR_BYTES",
            "QUANT_DESCRIPTOR_SIZE": "QUANT_DESCRIPTOR_BYTES",
        }
        for key, value in expected.items():
            self.assertRegex(c_header, rf"#define\s+{c_names[key]}\s+{value}u")
            self.assertRegex(sv_package, rf"{sv_names[key]}\s*=\s*{value};")

    def test_complete_valid_model(self):
        validate_model(*valid_model())

    def test_complete_package_integrity_and_parse(self):
        package = encoded_valid_package()
        header, layers, tensors, quant = parse_model_package(package)
        self.assertEqual(header.model_id, 7)
        self.assertEqual([layer.layer_id for layer in layers], [0])
        self.assertEqual([tensor.tensor_id for tensor in tensors], [0, 1])
        self.assertEqual([item.quantization_id for item in quant], [0])

        corrupted = bytearray(package)
        corrupted[-1] ^= 1
        with self.assertRaisesRegex(AbiError, "SHA-256 mismatch"):
            parse_model_package(bytes(corrupted))

    def test_rejects_parameter_corruption_even_with_rebuilt_package_checksums(self):
        package = bytearray(encoded_valid_package())
        package[512] ^= 1
        header = ModelHeader.unpack(package[:MODEL_HEADER_SIZE])
        header = dataclasses.replace(
            header, package_crc32=0, package_sha256=bytes(32)
        )
        package[:MODEL_HEADER_SIZE] = header.pack()
        header = dataclasses.replace(header, package_sha256=compute_package_sha256(package))
        package[:MODEL_HEADER_SIZE] = header.pack()
        header = dataclasses.replace(header, package_crc32=compute_package_crc32(package))
        package[:MODEL_HEADER_SIZE] = header.pack()
        with self.assertRaisesRegex(AbiError, "parameter CRC32 mismatch"):
            parse_model_package(bytes(package))

    def test_rejects_live_tensor_allocation_overlap(self):
        header, layers, tensors, quant = valid_model()
        tensors[1] = dataclasses.replace(tensors[1], ddr_offset=32)
        with self.assertRaisesRegex(AbiError, "overlap in DDR"):
            validate_model(header, layers, tensors, quant)

    def test_rejects_unsupported_quantization(self):
        header, layers, tensors, quant = valid_model()
        quant[0] = dataclasses.replace(quant[0], quant_multiplier=17)
        with self.assertRaisesRegex(AbiError, "multiplier=1"):
            validate_model(header, layers, tensors, quant)

    def test_rejects_tensor_beyond_functional_maximum(self):
        header, layers, tensors, quant = valid_model()
        tensors[0] = dataclasses.replace(tensors[0], width=1025, row_stride=3075,
                                         allocation_size=12300)
        with self.assertRaisesRegex(AbiError, "width is outside"):
            validate_model(header, layers, tensors, quant)

    def test_rejects_wrong_parameter_length(self):
        header, layers, tensors, quant = valid_model()
        layers[0] = dataclasses.replace(layers[0], weight_size=80)
        with self.assertRaisesRegex(AbiError, "weight payload size"):
            validate_model(header, layers, tensors, quant)

    def test_rejects_residual_quantization_mismatch(self):
        header, layers, tensors, quant = valid_model()
        quant.append(QuantizationDescriptor(1))
        header = dataclasses.replace(header, quantization_count=2)
        tensors[0] = dataclasses.replace(tensors[0], quantization_id=1)
        layers[0] = dataclasses.replace(
            layers[0], residual_mode=ResidualMode.POST_QUANT_SUBTRACT,
            residual_tensor_id=0,
        )
        with self.assertRaisesRegex(AbiError, "quantization IDs must match"):
            validate_model(header, layers, tensors, quant)


if __name__ == "__main__":
    unittest.main()
