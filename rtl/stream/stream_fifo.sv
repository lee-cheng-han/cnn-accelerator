`timescale 1ns/1ps
module stream_fifo #(
  parameter int DATA_WIDTH = 8,
  parameter int DEPTH = 16
)(
  input  logic clk,
  input  logic rst_n,
  input  logic wr_en,
  input  logic [DATA_WIDTH-1:0] wr_data,
  input  logic rd_en,
  output logic [DATA_WIDTH-1:0] rd_data,
  output logic full,
  output logic empty,
  output logic [$clog2(DEPTH+1)-1:0] level
);
  localparam int PTR_WIDTH = $clog2(DEPTH);
  logic [DATA_WIDTH-1:0] mem[DEPTH];
  logic [PTR_WIDTH-1:0] wr_ptr, rd_ptr;

  assign full  = (level == DEPTH);
  assign empty = (level == 0);
  assign rd_data = mem[rd_ptr];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= '0; rd_ptr <= '0; level <= '0;
    end else begin
      if (wr_en && !full) begin
        mem[wr_ptr] <= wr_data;
        wr_ptr <= wr_ptr + 1'b1;
      end
      if (rd_en && !empty) begin
        rd_ptr <= rd_ptr + 1'b1;
      end
      unique case ({wr_en && !full, rd_en && !empty})
        2'b10: level <= level + 1'b1;
        2'b01: level <= level - 1'b1;
        default: level <= level;
      endcase
    end
  end
endmodule
