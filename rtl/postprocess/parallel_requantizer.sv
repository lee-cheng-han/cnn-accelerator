`timescale 1ns/1ps

module parallel_requantizer #(
  parameter int PK = 8,
  parameter int ACC_W = 32,
  parameter int OUT_W = 8
)(
  input  logic clk,
  input  logic rst_n,
  input  logic valid_in,
  input  logic signed [ACC_W-1:0] acc_in [PK],
  input  logic signed [31:0] quant_multiplier [PK],
  input  logic [5:0] quant_shift [PK],
  input  logic signed [7:0] output_zero_point [PK],
  input  logic [PK-1:0] lane_mask,
  output wire signed [OUT_W-1:0] out_vec [PK],
  output wire [PK-1:0] saturation_positive,
  output wire [PK-1:0] saturation_negative,
  output logic valid_out
);

  localparam logic signed [63:0] MAX_VAL = (64'sd1 <<< (OUT_W - 1)) - 64'sd1;
  localparam logic signed [63:0] MIN_VAL = -(64'sd1 <<< (OUT_W - 1));
  logic [OUT_W+1:0] result_q [PK];

  function automatic logic [OUT_W+1:0] requantize_value(
    input logic signed [ACC_W-1:0] accumulator,
    input logic signed [31:0] multiplier,
    input logic [5:0] shift,
    input logic signed [7:0] zero_point,
    input logic enable
  );
    logic signed [63:0] product;
    logic signed [63:0] rounded;
    logic signed [63:0] shifted;
    logic negative_product;
    logic [63:0] magnitude;
    logic [63:0] quotient;
    logic [63:0] remainder;
    logic [63:0] half;
    logic [63:0] mask;
    logic signed [OUT_W-1:0] result;
    logic positive;
    logic negative;
    begin
      product = '0;
      rounded = '0;
      shifted = '0;
      negative_product = 1'b0;
      magnitude = '0;
      quotient = '0;
      remainder = '0;
      half = '0;
      mask = '0;
      result = '0;
      positive = 1'b0;
      negative = 1'b0;
      if (enable) begin
        product = $signed(accumulator) * $signed(multiplier);
        if (shift == 0) begin
          rounded = product;
        end else if (shift <= 6'd62) begin
          negative_product = product < 0;
          magnitude = negative_product ? $unsigned(-product) : $unsigned(product);
          quotient = magnitude >> shift;
          mask = (64'h1 << shift) - 64'd1;
          remainder = magnitude & mask;
          half = 64'h1 << (shift - 6'd1);
          if ((remainder > half) || ((remainder == half) && quotient[0])) begin
            quotient = quotient + 64'd1;
          end
          rounded = negative_product ? -$signed(quotient) : $signed(quotient);
        end
        shifted = rounded + $signed({{56{zero_point[7]}}, zero_point});
        if (shifted > MAX_VAL) begin
          result = {1'b0, {(OUT_W-1){1'b1}}};
          positive = 1'b1;
        end else if (shifted < MIN_VAL) begin
          result = {1'b1, {(OUT_W-1){1'b0}}};
          negative = 1'b1;
        end else begin
          result = shifted[OUT_W-1:0];
        end
      end
      requantize_value = {positive, negative, result};
    end
  endfunction

  for (genvar pk = 0; pk < PK; pk++) begin : g_result_outputs
    assign out_vec[pk] = result_q[pk][OUT_W-1:0];
    assign saturation_negative[pk] = result_q[pk][OUT_W];
    assign saturation_positive[pk] = result_q[pk][OUT_W+1];
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_out <= 1'b0;
      for (int pk = 0; pk < PK; pk++) begin
        result_q[pk] <= '0;
      end
    end else begin
      valid_out <= valid_in;
      if (valid_in) begin
        for (int pk = 0; pk < PK; pk++) begin
          result_q[pk] <= requantize_value(
            acc_in[pk], quant_multiplier[pk], quant_shift[pk],
            output_zero_point[pk], lane_mask[pk]
          );
        end
      end
    end
  end
endmodule
