`default_nettype none
`timescale 1ns/1ps

package cnn_accel_abi_pkg;
  localparam int unsigned ABI_VERSION = 1;
  localparam logic [31:0] MODEL_MAGIC = 32'h314E_4E43;
  localparam int unsigned MODEL_HEADER_BYTES = 128;
  localparam int unsigned LAYER_DESCRIPTOR_BYTES = 128;
  localparam int unsigned TENSOR_DESCRIPTOR_BYTES = 64;
  localparam int unsigned QUANT_DESCRIPTOR_BYTES = 32;
  localparam int unsigned RECORD_ALIGNMENT_BYTES = 64;
  localparam logic [15:0] NO_TENSOR_ID = 16'hFFFF;

  localparam int unsigned MAX_LAYERS = 8;
  localparam int unsigned MAX_TENSORS = 32;
  localparam int unsigned MAX_QUANTIZATIONS = 32;
  localparam int unsigned MAX_CHANNELS = 16;
  localparam int unsigned MAX_TENSOR_WIDTH = 1024;
  localparam int unsigned MAX_TENSOR_HEIGHT = 1024;
  localparam int unsigned MAX_LAYER_WEIGHT_BYTES = 2304;
  localparam int unsigned MAX_LAYER_BIAS_BYTES = 64;
  localparam int unsigned WEIGHT_BANK_CAPACITY_BYTES = 4096;
  localparam int unsigned BIAS_BANK_CAPACITY_BYTES = 256;

  typedef enum logic [15:0] {
    OPCODE_CONV2D = 16'd1
  } opcode_e;

  typedef enum logic [7:0] {
    ACTIVATION_NONE = 8'd0,
    ACTIVATION_RELU = 8'd1
  } activation_e;

  typedef enum logic [7:0] {
    RESIDUAL_NONE = 8'd0,
    RESIDUAL_POST_QUANT_ADD = 8'd1,
    RESIDUAL_POST_QUANT_SUBTRACT = 8'd2
  } residual_mode_e;

  typedef enum logic [7:0] {
    ROUND_ARITHMETIC_SHIFT = 8'd0
  } rounding_mode_e;

  localparam logic [31:0] LAYER_FLAG_BIAS_ENABLE = 32'h0000_0001;
  localparam logic [31:0] LAYER_FLAG_LAST_LAYER = 32'h0000_0002;
  localparam logic [15:0] TENSOR_FLAG_MODEL_INPUT = 16'h0001;
  localparam logic [15:0] TENSOR_FLAG_MODEL_OUTPUT = 16'h0002;
  localparam logic [15:0] TENSOR_FLAG_CONSTANT = 16'h0004;

  localparam int unsigned MH_PACKAGE_SIZE_OFS = 8;
  localparam int unsigned MH_LAYER_COUNT_OFS = 24;
  localparam int unsigned MH_LAYER_TABLE_OFS = 32;
  localparam int unsigned MH_TENSOR_TABLE_OFS = 36;
  localparam int unsigned MH_QUANT_TABLE_OFS = 40;
  localparam int unsigned MH_PARAMETER_DATA_OFS = 44;
  localparam int unsigned MH_PACKAGE_CRC32_OFS = 56;
  localparam int unsigned MH_INPUT_TENSOR_ID_OFS = 60;
  localparam int unsigned MH_PACKAGE_SHA256_OFS = 64;

  localparam int unsigned LD_LAYER_ID_OFS = 4;
  localparam int unsigned LD_INPUT_TENSOR_ID_OFS = 12;
  localparam int unsigned LD_WEIGHT_OFFSET_OFS = 20;
  localparam int unsigned LD_PARAMETER_CRC32_OFS = 36;
  localparam int unsigned LD_GEOMETRY_OFS = 40;
  localparam int unsigned LD_TILE_HINT_OFS = 52;

  localparam int unsigned TD_TENSOR_ID_OFS = 4;
  localparam int unsigned TD_DDR_OFFSET_OFS = 8;
  localparam int unsigned TD_WIDTH_OFS = 20;
  localparam int unsigned TD_ROW_STRIDE_OFS = 36;

  localparam int unsigned QD_QUANTIZATION_ID_OFS = 4;
  localparam int unsigned QD_MULTIPLIER_OFS = 8;
  localparam int unsigned QD_SHIFT_OFS = 12;
endpackage

`default_nettype wire
