`timescale 1ns/1ps
module window_generator_3x3 #(
  parameter int DATA_WIDTH = 8
)(
  input  logic signed [DATA_WIDTH-1:0] taps[9],
  input  logic taps_valid,
  output logic signed [DATA_WIDTH-1:0] window[9],
  output logic window_valid
);
  assign window = taps;
  assign window_valid = taps_valid;
endmodule
