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
  input  logic clk,
  input  logic rst_n,
  input  logic pipe_en,
  input  logic valid_in,

  // 0 = 1x1 convolution, 1 = 3x3 convolution
  input  logic kernel_mode,

  input  logic signed [DATA_WIDTH-1:0]   windows [NUM_INPUT_CHANNELS][KERNEL_TAPS],
  input  logic signed [WEIGHT_WIDTH-1:0] weights [NUM_INPUT_CHANNELS][KERNEL_TAPS],
  input  logic signed [BIAS_WIDTH-1:0]   bias,
  input  logic                           relu_enable,
  input  logic                           bias_enable,
  input  logic                           quant_enable,
  input  logic [4:0]                     quant_shift,

  output logic valid_out,
  output logic signed [ACC_WIDTH-1:0]    acc_raw,
  output logic signed [OUT_WIDTH-1:0]    out_data
);

  localparam int PRODUCT_WIDTH = DATA_WIDTH + WEIGHT_WIDTH;

  logic valid_s1;
  logic valid_s2;
  logic valid_s3;
  logic valid_s4;

  logic kernel_mode_s1;
  logic kernel_mode_s2;
  logic kernel_mode_s3;

  logic signed [PRODUCT_WIDTH-1:0] products_s1
    [NUM_INPUT_CHANNELS][KERNEL_TAPS];

  logic signed [ACC_WIDTH-1:0] channel_sums_s2
    [NUM_INPUT_CHANNELS];

  logic signed [ACC_WIDTH-1:0] acc_s3;
  logic signed [ACC_WIDTH-1:0] acc_bias_s4;
  logic signed [ACC_WIDTH-1:0] acc_relu_s4;
  logic signed [ACC_WIDTH-1:0] acc_quant_s4;

  logic signed [BIAS_WIDTH-1:0] bias_s1;
  logic signed [BIAS_WIDTH-1:0] bias_s2;
  logic signed [BIAS_WIDTH-1:0] bias_s3;

  logic relu_enable_s1;
  logic relu_enable_s2;
  logic relu_enable_s3;

  logic bias_enable_s1;
  logic bias_enable_s2;
  logic bias_enable_s3;

  logic quant_enable_s1;
  logic quant_enable_s2;
  logic quant_enable_s3;

  logic [4:0] quant_shift_s1;
  logic [4:0] quant_shift_s2;
  logic [4:0] quant_shift_s3;

  function automatic logic signed [ACC_WIDTH-1:0] sign_extend_product(
    input logic signed [PRODUCT_WIDTH-1:0] value
  );
    sign_extend_product = {{(ACC_WIDTH-PRODUCT_WIDTH){value[PRODUCT_WIDTH-1]}}, value};
  endfunction

  function automatic logic signed [ACC_WIDTH-1:0] sum_kernel_products(
    input logic signed [PRODUCT_WIDTH-1:0] p [KERNEL_TAPS],
    input logic use_3x3
  );
    logic signed [ACC_WIDTH-1:0] sum;
    begin
      sum = '0;

      if (use_3x3) begin
        for (int k = 0; k < KERNEL_TAPS; k++) begin
          sum = sum + sign_extend_product(p[k]);
        end
      end else begin
        // 1x1 mode: only tap 0 participates.
        sum = sign_extend_product(p[0]);
      end

      sum_kernel_products = sum;
    end
  endfunction

  function automatic logic signed [ACC_WIDTH-1:0] saturating_postprocess(
    input logic signed [ACC_WIDTH-1:0] acc_in,
    input logic signed [BIAS_WIDTH-1:0] bias_in,
    input logic bias_en,
    input logic relu_en,
    input logic quant_en,
    input logic [4:0] shift_in
  );
    logic signed [ACC_WIDTH-1:0] tmp_bias;
    logic signed [ACC_WIDTH-1:0] tmp_relu;
    logic signed [ACC_WIDTH-1:0] tmp_quant;
    begin
      if (bias_en) begin
        tmp_bias = acc_in + ACC_WIDTH'(bias_in);
      end else begin
        tmp_bias = acc_in;
      end

      if (relu_en && tmp_bias[ACC_WIDTH-1]) begin
        tmp_relu = '0;
      end else begin
        tmp_relu = tmp_bias;
      end

      if (quant_en) begin
        tmp_quant = tmp_relu >>> shift_in;
      end else begin
        tmp_quant = tmp_relu;
      end

      saturating_postprocess = tmp_quant;
    end
  endfunction

  function automatic logic signed [OUT_WIDTH-1:0] saturate_to_out(
    input logic signed [ACC_WIDTH-1:0] value
  );
    logic signed [ACC_WIDTH-1:0] max_val;
    logic signed [ACC_WIDTH-1:0] min_val;
    begin
      max_val = (ACC_WIDTH'(1) <<< (OUT_WIDTH - 1)) - ACC_WIDTH'(1);
      min_val = -(ACC_WIDTH'(1) <<< (OUT_WIDTH - 1));

      if (value > max_val) begin
        saturate_to_out = {1'b0, {(OUT_WIDTH-1){1'b1}}};
      end else if (value < min_val) begin
        saturate_to_out = {1'b1, {(OUT_WIDTH-1){1'b0}}};
      end else begin
        saturate_to_out = value[OUT_WIDTH-1:0];
      end
    end
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_s1  <= 1'b0;
      valid_s2  <= 1'b0;
      valid_s3  <= 1'b0;
      valid_s4  <= 1'b0;
      acc_raw   <= '0;
      out_data  <= '0;

      kernel_mode_s1 <= 1'b1;
      kernel_mode_s2 <= 1'b1;
      kernel_mode_s3 <= 1'b1;

      bias_s1 <= '0;
      bias_s2 <= '0;
      bias_s3 <= '0;

      relu_enable_s1  <= 1'b0;
      relu_enable_s2  <= 1'b0;
      relu_enable_s3  <= 1'b0;

      bias_enable_s1  <= 1'b0;
      bias_enable_s2  <= 1'b0;
      bias_enable_s3  <= 1'b0;

      quant_enable_s1 <= 1'b0;
      quant_enable_s2 <= 1'b0;
      quant_enable_s3 <= 1'b0;

      quant_shift_s1  <= 5'd0;
      quant_shift_s2  <= 5'd0;
      quant_shift_s3  <= 5'd0;

      for (int c = 0; c < NUM_INPUT_CHANNELS; c++) begin
        channel_sums_s2[c] <= '0;

        for (int k = 0; k < KERNEL_TAPS; k++) begin
          products_s1[c][k] <= '0;
        end
      end

      acc_s3       <= '0;
      acc_bias_s4  <= '0;
      acc_relu_s4  <= '0;
      acc_quant_s4 <= '0;
    end else if (pipe_en) begin
      // Stage 1: multiply pixels by weights.
      valid_s1 <= valid_in;

      kernel_mode_s1  <= kernel_mode;
      bias_s1         <= bias;
      relu_enable_s1  <= relu_enable;
      bias_enable_s1  <= bias_enable;
      quant_enable_s1 <= quant_enable;
      quant_shift_s1  <= quant_shift;

      for (int c = 0; c < NUM_INPUT_CHANNELS; c++) begin
        for (int k = 0; k < KERNEL_TAPS; k++) begin
          products_s1[c][k] <= $signed(windows[c][k]) * $signed(weights[c][k]);
        end
      end

      // Stage 2: sum products per channel.
      // 3x3 mode sums all 9 products.
      // 1x1 mode only uses tap 0.
      valid_s2 <= valid_s1;

      kernel_mode_s2  <= kernel_mode_s1;
      bias_s2         <= bias_s1;
      relu_enable_s2  <= relu_enable_s1;
      bias_enable_s2  <= bias_enable_s1;
      quant_enable_s2 <= quant_enable_s1;
      quant_shift_s2  <= quant_shift_s1;

      for (int c = 0; c < NUM_INPUT_CHANNELS; c++) begin
        channel_sums_s2[c] <= sum_kernel_products(products_s1[c], kernel_mode_s1);
      end

      // Stage 3: accumulate input channels.
      valid_s3 <= valid_s2;

      kernel_mode_s3  <= kernel_mode_s2;
      bias_s3         <= bias_s2;
      relu_enable_s3  <= relu_enable_s2;
      bias_enable_s3  <= bias_enable_s2;
      quant_enable_s3 <= quant_enable_s2;
      quant_shift_s3  <= quant_shift_s2;

      acc_s3 <= channel_sums_s2[0] + channel_sums_s2[1] + channel_sums_s2[2];

      // Stage 4: postprocess and saturate.
      valid_s4 <= valid_s3;

      acc_bias_s4 <= saturating_postprocess(
        acc_s3,
        bias_s3,
        bias_enable_s3,
        relu_enable_s3,
        quant_enable_s3,
        quant_shift_s3
      );

      acc_relu_s4  <= acc_bias_s4;
      acc_quant_s4 <= acc_bias_s4;

      acc_raw  <= acc_s3;
      out_data <= saturate_to_out(
        saturating_postprocess(
          acc_s3,
          bias_s3,
          bias_enable_s3,
          relu_enable_s3,
          quant_enable_s3,
          quant_shift_s3
        )
      );
    end
  end

  assign valid_out = valid_s4;

endmodule
