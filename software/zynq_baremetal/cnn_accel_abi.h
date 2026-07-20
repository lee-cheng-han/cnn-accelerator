#ifndef CNN_ACCEL_ABI_H
#define CNN_ACCEL_ABI_H

#include <stdint.h>

/* Frozen V1 model-package ABI. Records are serialized explicitly; do not cast
 * untrusted package memory to native C structs. */
#define CNN_ABI_VERSION                    1u
#define CNN_MODEL_MAGIC                    0x314E4E43u
#define CNN_MODEL_HEADER_SIZE              128u
#define CNN_LAYER_DESCRIPTOR_SIZE          128u
#define CNN_TENSOR_DESCRIPTOR_SIZE          64u
#define CNN_QUANT_DESCRIPTOR_SIZE           32u
#define CNN_ABI_RECORD_ALIGNMENT            64u
#define CNN_NO_TENSOR_ID                 0xFFFFu

#define CNN_MAX_LAYERS                       8u
#define CNN_MAX_TENSORS                     32u
#define CNN_MAX_QUANTIZATIONS               32u
#define CNN_MAX_CHANNELS                    16u
#define CNN_MAX_TENSOR_WIDTH              1024u
#define CNN_MAX_TENSOR_HEIGHT             1024u
#define CNN_MAX_LAYER_WEIGHT_BYTES        2304u
#define CNN_MAX_LAYER_BIAS_BYTES            64u
#define CNN_WEIGHT_BANK_CAPACITY_BYTES    4096u
#define CNN_BIAS_BANK_CAPACITY_BYTES       256u

enum cnn_opcode {
    CNN_OPCODE_CONV2D = 1
};

enum cnn_activation {
    CNN_ACTIVATION_NONE = 0,
    CNN_ACTIVATION_RELU = 1
};

enum cnn_residual_mode {
    CNN_RESIDUAL_NONE = 0,
    CNN_RESIDUAL_POST_QUANT_ADD = 1,
    CNN_RESIDUAL_POST_QUANT_SUBTRACT = 2
};

enum cnn_rounding_mode {
    CNN_ROUND_ARITHMETIC_SHIFT = 0
};

enum cnn_element_type {
    CNN_ELEMENT_INT8 = 1
};

enum cnn_tensor_layout {
    CNN_LAYOUT_NHWC = 1
};

#define CNN_LAYER_FLAG_BIAS_ENABLE  (1u << 0)
#define CNN_LAYER_FLAG_LAST_LAYER   (1u << 1)
#define CNN_TENSOR_FLAG_MODEL_INPUT (1u << 0)
#define CNN_TENSOR_FLAG_MODEL_OUTPUT (1u << 1)
#define CNN_TENSOR_FLAG_CONSTANT    (1u << 2)

/* Byte offsets are the normative interface for software serializers. */
#define CNN_MH_PACKAGE_SIZE_OFS       8u
#define CNN_MH_LAYER_COUNT_OFS       24u
#define CNN_MH_LAYER_TABLE_OFS       32u
#define CNN_MH_TENSOR_TABLE_OFS      36u
#define CNN_MH_QUANT_TABLE_OFS       40u
#define CNN_MH_PARAMETER_DATA_OFS    44u
#define CNN_MH_PACKAGE_CRC32_OFS     56u
#define CNN_MH_INPUT_TENSOR_ID_OFS   60u
#define CNN_MH_PACKAGE_SHA256_OFS    64u

#define CNN_LD_LAYER_ID_OFS           4u
#define CNN_LD_INPUT_TENSOR_ID_OFS   12u
#define CNN_LD_WEIGHT_OFFSET_OFS     20u
#define CNN_LD_PARAMETER_CRC32_OFS   36u
#define CNN_LD_GEOMETRY_OFS          40u
#define CNN_LD_TILE_HINT_OFS         52u

#define CNN_TD_TENSOR_ID_OFS          4u
#define CNN_TD_DDR_OFFSET_OFS         8u
#define CNN_TD_WIDTH_OFS             20u
#define CNN_TD_ROW_STRIDE_OFS        36u

#define CNN_QD_QUANTIZATION_ID_OFS    4u
#define CNN_QD_MULTIPLIER_OFS         8u
#define CNN_QD_SHIFT_OFS             12u

#endif
