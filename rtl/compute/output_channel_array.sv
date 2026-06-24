`timescale 1ns/1ps

module output_channel_array #(
  parameter int DATA_WIDTH = 8,
  parameter int WEIGHT_WIDTH = 8,
  parameter int ACC_WIDTH = 32,
  parameter int OUT_WIDTH = 8,
  parameter int BIAS_WIDTH = 32,
  parameter int NUM_INPUT_CHANNELS = 3,
  parameter int NUM_OUTPUT_CHANNELS = 4,
  parameter int KERNEL_TAPS = 9
)(
  input  logic clk,
  input  logic rst_n,
  input  logic pipe_en,
  input  logic valid_in,

  // 0 = 1x1 convolution, 1 = 3x3 convolution
  input  logic kernel_mode,

  input  logic signed [DATA_WIDTH-1:0]   windows [NUM_INPUT_CHANNELS][KERNEL_TAPS],
  input  logic signed [WEIGHT_WIDTH-1:0] weights [NUM_OUTPUT_CHANNELS][NUM_INPUT_CHANNELS][KERNEL_TAPS],
  input  logic signed [BIAS_WIDTH-1:0]   bias    [NUM_OUTPUT_CHANNELS],

  input  logic                           relu_enable,
  input  logic                           bias_enable,
  input  logic                           quant_enable,
  input  logic [4:0]                     quant_shift,

  output logic                           valid_out [NUM_OUTPUT_CHANNELS],
  output logic signed [ACC_WIDTH-1:0]    acc_raw   [NUM_OUTPUT_CHANNELS],
  output logic signed [OUT_WIDTH-1:0]    out_data  [NUM_OUTPUT_CHANNELS]
);

  genvar oc;

  generate
    for (oc = 0; oc < NUM_OUTPUT_CHANNELS; oc++) begin : GEN_OC
      conv_engine #(
        .DATA_WIDTH(DATA_WIDTH),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .OUT_WIDTH(OUT_WIDTH),
        .BIAS_WIDTH(BIAS_WIDTH),
        .NUM_INPUT_CHANNELS(NUM_INPUT_CHANNELS),
        .KERNEL_TAPS(KERNEL_TAPS)
      ) u_conv_engine (
        .clk(clk),
        .rst_n(rst_n),
        .pipe_en(pipe_en),
        .valid_in(valid_in),
        .kernel_mode(kernel_mode),

        .windows(windows),
        .weights(weights[oc]),
        .bias(bias[oc]),

        .relu_enable(relu_enable),
        .bias_enable(bias_enable),
        .quant_enable(quant_enable),
        .quant_shift(quant_shift),

        .valid_out(valid_out[oc]),
        .acc_raw(acc_raw[oc]),
        .out_data(out_data[oc])
      );
    end
  endgenerate

endmodule
