`timescale 1ns/1ps

module denoise_layer_descriptor_rom #(
  parameter int ADDR_W = 32,
  parameter int DIM_W  = 16,
  parameter int CH_W   = 8,
  parameter logic [ADDR_W-1:0] INPUT_BASE  = 32'h0000_0000,
  parameter logic [ADDR_W-1:0] FEATURE_A_BASE = 32'h0010_0000,
  parameter logic [ADDR_W-1:0] FEATURE_B_BASE = 32'h0020_0000,
  parameter logic [ADDR_W-1:0] OUTPUT_BASE = 32'h0030_0000,
  parameter logic [ADDR_W-1:0] WEIGHT_BASE = 32'h0040_0000,
  parameter logic [ADDR_W-1:0] BIAS_BASE   = 32'h0050_0000,
  parameter bit FINAL_RESIDUAL_ENABLE = 1'b1
)(
  input  logic [1:0] layer_index,
  input  logic [DIM_W-1:0] image_width,
  input  logic [DIM_W-1:0] image_height,

  output logic valid,
  output logic [ADDR_W-1:0] input_base,
  output logic [ADDR_W-1:0] output_base,
  output logic [ADDR_W-1:0] weight_base,
  output logic [ADDR_W-1:0] bias_base,
  output logic [DIM_W-1:0] input_width,
  output logic [DIM_W-1:0] input_height,
  output logic [CH_W-1:0] input_channels,
  output logic [CH_W-1:0] output_channels,
  output logic [1:0] kernel_size,
  output logic [1:0] stride,
  output logic [1:0] padding,
  output logic bias_enable,
  output logic relu_enable,
  output logic quant_enable,
  output logic [4:0] quant_shift,
  output logic residual_enable,
  output logic [ADDR_W-1:0] residual_input_base
);

  localparam logic [ADDR_W-1:0] L0_WEIGHT_OFFSET = 32'h0000_0000;
  localparam logic [ADDR_W-1:0] L1_WEIGHT_OFFSET = 32'h0000_1000;
  localparam logic [ADDR_W-1:0] L2_WEIGHT_OFFSET = 32'h0000_3000;
  localparam logic [ADDR_W-1:0] L0_BIAS_OFFSET   = 32'h0000_0000;
  localparam logic [ADDR_W-1:0] L1_BIAS_OFFSET   = 32'h0000_0100;
  localparam logic [ADDR_W-1:0] L2_BIAS_OFFSET   = 32'h0000_0200;

  always_comb begin
    valid = 1'b1;
    input_width = image_width;
    input_height = image_height;
    kernel_size = 2'd3;
    stride = 2'd1;
    padding = 2'd1;
    bias_enable = 1'b1;
    quant_enable = 1'b1;
    quant_shift = 5'd0;
    residual_enable = 1'b0;
    residual_input_base = INPUT_BASE;

    unique case (layer_index)
      2'd0: begin
        input_base = INPUT_BASE;
        output_base = FEATURE_A_BASE;
        weight_base = WEIGHT_BASE + L0_WEIGHT_OFFSET;
        bias_base = BIAS_BASE + L0_BIAS_OFFSET;
        input_channels = CH_W'(3);
        output_channels = CH_W'(16);
        relu_enable = 1'b1;
        quant_shift = 5'd0;
      end

      2'd1: begin
        input_base = FEATURE_A_BASE;
        output_base = FEATURE_B_BASE;
        weight_base = WEIGHT_BASE + L1_WEIGHT_OFFSET;
        bias_base = BIAS_BASE + L1_BIAS_OFFSET;
        input_channels = CH_W'(16);
        output_channels = CH_W'(16);
        relu_enable = 1'b1;
        quant_shift = 5'd5;
      end

      2'd2: begin
        input_base = FEATURE_B_BASE;
        output_base = OUTPUT_BASE;
        weight_base = WEIGHT_BASE + L2_WEIGHT_OFFSET;
        bias_base = BIAS_BASE + L2_BIAS_OFFSET;
        input_channels = CH_W'(16);
        output_channels = CH_W'(3);
        relu_enable = 1'b0;
        quant_shift = 5'd1;
        residual_enable = FINAL_RESIDUAL_ENABLE;
        residual_input_base = INPUT_BASE;
      end

      default: begin
        valid = 1'b0;
        input_base = '0;
        output_base = '0;
        weight_base = '0;
        bias_base = '0;
        input_channels = '0;
        output_channels = '0;
        relu_enable = 1'b0;
      end
    endcase
  end

endmodule
