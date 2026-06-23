`timescale 1ns/1ps
module line_buffer_3x3 #(
  parameter int DATA_WIDTH = 8,
  parameter int IMG_WIDTH = 32
)(
  input  logic clk,
  input  logic rst_n,
  input  logic pixel_valid,
  input  logic signed [DATA_WIDTH-1:0] pixel_in,
  output logic window_valid,
  output logic signed [DATA_WIDTH-1:0] taps[9]
);
  logic signed [DATA_WIDTH-1:0] line0[IMG_WIDTH];
  logic signed [DATA_WIDTH-1:0] line1[IMG_WIDTH];
  logic signed [DATA_WIDTH-1:0] sr0[3], sr1[3], sr2[3];
  logic [$clog2(IMG_WIDTH)-1:0] col;
  logic [15:0] row;
  integer i;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      col <= '0; row <= '0; window_valid <= 1'b0;
      for (i = 0; i < 3; i++) begin sr0[i] <= '0; sr1[i] <= '0; sr2[i] <= '0; end
    end else if (pixel_valid) begin
      sr0[0] <= sr0[1]; sr0[1] <= sr0[2]; sr0[2] <= line1[col];
      sr1[0] <= sr1[1]; sr1[1] <= sr1[2]; sr1[2] <= line0[col];
      sr2[0] <= sr2[1]; sr2[1] <= sr2[2]; sr2[2] <= pixel_in;
      line1[col] <= line0[col];
      line0[col] <= pixel_in;
      window_valid <= (row >= 2 && col >= 2);
      if (col == IMG_WIDTH-1) begin col <= '0; row <= row + 1'b1; end
      else col <= col + 1'b1;
    end else begin
      window_valid <= 1'b0;
    end
  end

  assign taps[0] = sr0[0]; assign taps[1] = sr0[1]; assign taps[2] = sr0[2];
  assign taps[3] = sr1[0]; assign taps[4] = sr1[1]; assign taps[5] = sr1[2];
  assign taps[6] = sr2[0]; assign taps[7] = sr2[1]; assign taps[8] = sr2[2];
endmodule
