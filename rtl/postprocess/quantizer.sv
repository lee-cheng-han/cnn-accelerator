`timescale 1ns/1ps
module quantizer #(
  parameter int ACC_WIDTH = 32
)(
  input  logic signed [ACC_WIDTH-1:0] acc_in,
  input  logic [4:0]                  shift,
  input  logic                        enable,
  output logic signed [ACC_WIDTH-1:0] acc_out
);
  always_comb begin
    acc_out = enable ? (acc_in >>> shift) : acc_in;
  end
endmodule
