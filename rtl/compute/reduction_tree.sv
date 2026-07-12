`timescale 1ns/1ps

module reduction_tree #(
  parameter int N      = 4,
  parameter int IN_W   = 16,
  parameter int ACC_W  = 32
)(
  input  logic clk,
  input  logic rst_n,

  input  logic signed [IN_W-1:0] in_vec [N],
  input  logic                   valid_in,

  output logic signed [ACC_W-1:0] sum_out,
  output logic                    valid_out
);

  logic signed [ACC_W-1:0] sum_comb;

  always_comb begin
    sum_comb = '0;

    for (int i = 0; i < N; i++) begin
      sum_comb += {{(ACC_W-IN_W){in_vec[i][IN_W-1]}}, in_vec[i]};
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sum_out   <= '0;
      valid_out <= 1'b0;
    end else begin
      valid_out <= valid_in;

      if (valid_in) begin
        sum_out <= sum_comb;
      end
    end
  end

endmodule
