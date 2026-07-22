`timescale 1ns/1ps

module cnn_runtime_capabilities #(
  parameter int PC = 2,
  parameter int PK = 4,
  parameter int MAX_CIN = 16,
  parameter int MAX_COUT = 16,
  parameter int MAX_PIXELS = 16,
  parameter int CLOCK_HZ = 125_000_000
)(
  input  logic [4:0]  word_index,
  output logic [31:0] word_data
);
  import cnn_accel_abi_pkg::*;

  localparam logic [31:0] FIXED_FEATURES =
    FEATURE_CAPABILITY_QUERY |
    FEATURE_STRUCTURED_ERRORS |
    FEATURE_RUNTIME_METADATA |
    FEATURE_INTERRUPTS |
    FEATURE_FIXED_NETWORK;

  always_comb begin
    unique case (word_index)
      5'd0:  word_data = {16'(CAPABILITY_RECORD_BYTES), 16'(ABI_VERSION)};
      5'd1:  word_data = 32'h0004_0000;
      5'd2:  word_data = {16'd4, 16'(ABI_VERSION)};
      5'd3:  word_data = FIXED_FEATURES;
      5'd4:  word_data = 32'h0000_0002; // CONV2D opcode bit 1.
      5'd5:  word_data = 32'h0000_0002; // Signed INT8 element bit 1.
      5'd6:  word_data = 32'h0000_0003; // None and ReLU.
      5'd7:  word_data = 32'h0000_0001; // Arithmetic shift.
      5'd8:  word_data = 32'h0000_0005; // None and post-quant subtract.
      5'd9:  word_data = 32'h0000_0008; // Fixed 3x3 kernel.
      5'd10: word_data = 32'h0000_0002; // Fixed stride 1.
      5'd11: word_data = {16'd4, 16'd3};
      5'd12: word_data = {16'(MAX_CIN), 16'd3};
      5'd13: word_data = {16'(MAX_PIXELS), 16'(MAX_COUT)};
      5'd14: word_data = {16'd1, 16'(MAX_PIXELS)};
      5'd15: word_data = {16'd1, 16'd1};
      5'd16: word_data = 32'(MAX_PIXELS);
      5'd17: word_data = 32'(MAX_LAYER_WEIGHT_BYTES);
      5'd18: word_data = 32'(MAX_LAYER_BIAS_BYTES);
      5'd19: word_data = 32'(MAX_LAYER_WEIGHT_BYTES);
      5'd20: word_data = 32'(MAX_LAYER_BIAS_BYTES);
      5'd21: word_data = {16'd1, 16'd1};
      5'd22: word_data = {16'(PK), 16'(PC)};
      5'd23: word_data = 32'(CLOCK_HZ);
      default: word_data = 32'd0;
    endcase
  end
endmodule
