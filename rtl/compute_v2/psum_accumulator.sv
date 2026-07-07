`timescale 1ns/1ps

module psum_accumulator #(
  parameter int PK    = 8,
  parameter int ACC_W = 32
)(
  input  logic clk,
  input  logic rst_n,

  input  logic clear,
  input  logic accumulate,
  input  logic [PK-1:0] lane_mask,
  input  logic signed [ACC_W-1:0] add_vec [PK],

  output logic signed [ACC_W-1:0] psum_vec [PK]
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int pk = 0; pk < PK; pk++) begin
        psum_vec[pk] <= '0;
      end
    end else if (clear) begin
      for (int pk = 0; pk < PK; pk++) begin
        psum_vec[pk] <= '0;
      end
    end else if (accumulate) begin
      for (int pk = 0; pk < PK; pk++) begin
        if (lane_mask[pk]) begin
          psum_vec[pk] <= psum_vec[pk] + add_vec[pk];
        end
      end
    end
  end

endmodule
