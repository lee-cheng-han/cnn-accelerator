`timescale 1ns/1ps
module adder_tree #(
  parameter int IN_WIDTH = 16,
  parameter int OUT_WIDTH = 32,
  parameter int NUM_INPUTS = 9
)(
  input  logic signed [IN_WIDTH-1:0]  in_data[NUM_INPUTS],
  output logic signed [OUT_WIDTH-1:0] sum
);
  integer i;
  always_comb begin
    sum = '0;
    for (i = 0; i < NUM_INPUTS; i++) begin
      sum = sum + {{(OUT_WIDTH-IN_WIDTH){in_data[i][IN_WIDTH-1]}}, in_data[i]};
    end
  end
endmodule
