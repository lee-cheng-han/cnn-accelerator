`timescale 1ns/1ps
module weight_buffer #(
  parameter int WEIGHT_WIDTH = 8,
  parameter int BIAS_WIDTH = 32,
  parameter int NUM_INPUT_CHANNELS = 3,
  parameter int NUM_OUTPUT_CHANNELS = 4,
  parameter int KERNEL_TAPS = 9
)(
  input  logic signed [WEIGHT_WIDTH-1:0] cfg_weights[NUM_OUTPUT_CHANNELS][NUM_INPUT_CHANNELS][KERNEL_TAPS],
  input  logic signed [BIAS_WIDTH-1:0] cfg_bias[NUM_OUTPUT_CHANNELS],
  output logic signed [WEIGHT_WIDTH-1:0] weights[NUM_OUTPUT_CHANNELS][NUM_INPUT_CHANNELS][KERNEL_TAPS],
  output logic signed [BIAS_WIDTH-1:0] bias[NUM_OUTPUT_CHANNELS]
);
  assign weights = cfg_weights;
  assign bias = cfg_bias;
endmodule
