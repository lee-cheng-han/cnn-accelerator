`timescale 1ns/1ps
module channel_accumulator #(
  parameter int ACC_WIDTH = 32,
  parameter int NUM_INPUT_CHANNELS = 3
)(
  input  logic signed [ACC_WIDTH-1:0] channel_sums[NUM_INPUT_CHANNELS],
  output logic signed [ACC_WIDTH-1:0] acc_out
);
  integer c;
  always_comb begin
    acc_out = '0;
    for (c = 0; c < NUM_INPUT_CHANNELS; c++) begin
      acc_out = acc_out + channel_sums[c];
    end
  end
endmodule
