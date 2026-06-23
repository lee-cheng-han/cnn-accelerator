`timescale 1ns/1ps
module conv_engine #(
  parameter int DATA_WIDTH = 8,
  parameter int WEIGHT_WIDTH = 8,
  parameter int ACC_WIDTH = 32,
  parameter int OUT_WIDTH = 8,
  parameter int BIAS_WIDTH = 32,
  parameter int NUM_INPUT_CHANNELS = 3,
  parameter int KERNEL_TAPS = 9
)(
  input  logic signed [DATA_WIDTH-1:0]   windows [NUM_INPUT_CHANNELS][KERNEL_TAPS],
  input  logic signed [WEIGHT_WIDTH-1:0] weights [NUM_INPUT_CHANNELS][KERNEL_TAPS],
  input  logic signed [BIAS_WIDTH-1:0]   bias,
  input  logic                           relu_enable,
  input  logic                           bias_enable,
  input  logic                           quant_enable,
  input  logic [4:0]                     quant_shift,
  output logic signed [ACC_WIDTH-1:0]    acc_raw,
  output logic signed [OUT_WIDTH-1:0]    out_data
);
  logic signed [DATA_WIDTH+WEIGHT_WIDTH-1:0] products[NUM_INPUT_CHANNELS][KERNEL_TAPS];
  logic signed [ACC_WIDTH-1:0] channel_sums[NUM_INPUT_CHANNELS];
  logic signed [ACC_WIDTH-1:0] acc_bias;
  logic signed [ACC_WIDTH-1:0] acc_relu;
  logic signed [ACC_WIDTH-1:0] acc_quant;

  genvar c;
  generate
    for (c = 0; c < NUM_INPUT_CHANNELS; c++) begin : GEN_CH
      mac_array_3x3 #(
        .DATA_WIDTH(DATA_WIDTH), .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .PRODUCT_WIDTH(DATA_WIDTH+WEIGHT_WIDTH), .KERNEL_TAPS(KERNEL_TAPS)
      ) u_mac_array (
        .window(windows[c]), .weights(weights[c]), .enable(1'b1), .products(products[c])
      );

      adder_tree #(
        .IN_WIDTH(DATA_WIDTH+WEIGHT_WIDTH), .OUT_WIDTH(ACC_WIDTH), .NUM_INPUTS(KERNEL_TAPS)
      ) u_tree (
        .in_data(products[c]), .sum(channel_sums[c])
      );
    end
  endgenerate

  channel_accumulator #(.ACC_WIDTH(ACC_WIDTH), .NUM_INPUT_CHANNELS(NUM_INPUT_CHANNELS)) u_ch_acc (
    .channel_sums(channel_sums), .acc_out(acc_raw)
  );

  bias_add #(.ACC_WIDTH(ACC_WIDTH), .BIAS_WIDTH(BIAS_WIDTH)) u_bias (
    .acc_in(acc_raw), .bias(bias), .enable(bias_enable), .acc_out(acc_bias)
  );

  relu #(.ACC_WIDTH(ACC_WIDTH)) u_relu (
    .acc_in(acc_bias), .enable(relu_enable), .acc_out(acc_relu)
  );

  quantizer #(.ACC_WIDTH(ACC_WIDTH)) u_quant (
    .acc_in(acc_relu), .shift(quant_shift), .enable(quant_enable), .acc_out(acc_quant)
  );

  output_saturate #(.ACC_WIDTH(ACC_WIDTH), .OUT_WIDTH(OUT_WIDTH)) u_sat (
    .acc_in(acc_quant), .out_data(out_data)
  );
endmodule
