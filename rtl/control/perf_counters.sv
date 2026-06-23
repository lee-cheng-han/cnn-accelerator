`timescale 1ns/1ps
module perf_counters #(
  parameter int CNT_WIDTH = 32
)(
  input  logic clk,
  input  logic rst_n,
  input  logic clear,
  input  logic busy,
  input  logic input_fire,
  input  logic window_fire,
  input  logic output_fire,
  input  logic stall,
  input  logic fifo_full,
  input  logic [15:0] macs_per_window,
  output logic [CNT_WIDTH-1:0] cycle_count,
  output logic [CNT_WIDTH-1:0] input_pixel_count,
  output logic [CNT_WIDTH-1:0] window_count,
  output logic [CNT_WIDTH-1:0] mac_count,
  output logic [CNT_WIDTH-1:0] output_count,
  output logic [CNT_WIDTH-1:0] stall_count,
  output logic [CNT_WIDTH-1:0] fifo_full_count
);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || clear) begin
      cycle_count <= '0; input_pixel_count <= '0; window_count <= '0; mac_count <= '0;
      output_count <= '0; stall_count <= '0; fifo_full_count <= '0;
    end else begin
      if (busy)        cycle_count <= cycle_count + 1'b1;
      if (input_fire)  input_pixel_count <= input_pixel_count + 1'b1;
      if (window_fire) begin
        window_count <= window_count + 1'b1;
        mac_count <= mac_count + {16'd0, macs_per_window};
      end
      if (output_fire) output_count <= output_count + 1'b1;
      if (stall)       stall_count <= stall_count + 1'b1;
      if (fifo_full)   fifo_full_count <= fifo_full_count + 1'b1;
    end
  end
endmodule
