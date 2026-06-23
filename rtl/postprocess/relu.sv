`timescale 1ns/1ps
module relu #(
  parameter int ACC_WIDTH = 32
)(
  input  logic signed [ACC_WIDTH-1:0] acc_in,
  input  logic                        enable,
  output logic signed [ACC_WIDTH-1:0] acc_out
);
  always_comb begin
    if (enable && acc_in < 0) acc_out = '0;
    else                     acc_out = acc_in;
  end
endmodule
