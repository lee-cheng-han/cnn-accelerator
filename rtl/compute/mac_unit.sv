`timescale 1ns/1ps
module mac_unit #(
  parameter int DATA_WIDTH = 8,
  parameter int WEIGHT_WIDTH = 8,
  parameter int ACC_WIDTH = 32
)(
  input  logic signed [DATA_WIDTH-1:0]   pixel,
  input  logic signed [WEIGHT_WIDTH-1:0] weight,
  input  logic signed [ACC_WIDTH-1:0]    acc_in,
  input  logic                           enable,
  output logic signed [ACC_WIDTH-1:0]    acc_out
);
  always_comb begin
    if (enable) acc_out = acc_in + (pixel * weight);
    else        acc_out = acc_in;
  end
endmodule
