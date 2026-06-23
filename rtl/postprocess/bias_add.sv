`timescale 1ns/1ps
module bias_add #(
  parameter int ACC_WIDTH = 32,
  parameter int BIAS_WIDTH = 32
)(
  input  logic signed [ACC_WIDTH-1:0]  acc_in,
  input  logic signed [BIAS_WIDTH-1:0] bias,
  input  logic                         enable,
  output logic signed [ACC_WIDTH-1:0]  acc_out
);
  always_comb begin
    acc_out = enable ? acc_in + {{(ACC_WIDTH-BIAS_WIDTH){bias[BIAS_WIDTH-1]}}, bias} : acc_in;
  end
endmodule
