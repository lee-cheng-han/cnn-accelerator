`timescale 1ns/1ps
module activation_buffer #(
  parameter int DATA_WIDTH = 8,
  parameter int NUM_INPUT_CHANNELS = 3,
  parameter int MAX_PIXELS = 1024
)(
  input  logic clk,
  input  logic wr_en,
  input  logic [$clog2(NUM_INPUT_CHANNELS)-1:0] wr_channel,
  input  logic [$clog2(MAX_PIXELS)-1:0] wr_addr,
  input  logic signed [DATA_WIDTH-1:0] wr_data,
  input  logic [$clog2(MAX_PIXELS)-1:0] rd_addr[NUM_INPUT_CHANNELS][9],
  output logic signed [DATA_WIDTH-1:0] rd_window[NUM_INPUT_CHANNELS][9]
);
  logic signed [DATA_WIDTH-1:0] mem[NUM_INPUT_CHANNELS][MAX_PIXELS];
  integer c, k;

  always_ff @(posedge clk) begin
    if (wr_en) mem[wr_channel][wr_addr] <= wr_data;
  end

  always_comb begin
    for (c = 0; c < NUM_INPUT_CHANNELS; c++)
      for (k = 0; k < 9; k++)
        rd_window[c][k] = mem[c][rd_addr[c][k]];
  end
endmodule
