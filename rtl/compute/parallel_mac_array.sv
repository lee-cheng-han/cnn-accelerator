`timescale 1ns/1ps

module parallel_mac_array #(
  parameter int PC     = 4,
  parameter int PK     = 8,
  parameter int DATA_W = 8,
  parameter int PROD_W = 16,
  parameter int ACC_W  = 32
)(
  input  logic clk,
  input  logic rst_n,

  input  logic signed [DATA_W-1:0] act_vec [PC],
  input  logic signed [DATA_W-1:0] weight_mat [PK][PC],
  input  logic                     valid_in,

  output logic signed [ACC_W-1:0] dot_vec [PK],
  output logic                    valid_out
);

  logic signed [PROD_W-1:0] products_q [PK][PC];
  logic                     products_valid_q;
  logic                     reduce_valid [PK];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      products_valid_q <= 1'b0;

      for (int pk = 0; pk < PK; pk++) begin
        for (int pc = 0; pc < PC; pc++) begin
          products_q[pk][pc] <= '0;
        end
      end
    end else begin
      products_valid_q <= valid_in;

      if (valid_in) begin
        for (int pk = 0; pk < PK; pk++) begin
          for (int pc = 0; pc < PC; pc++) begin
            products_q[pk][pc] <= $signed(act_vec[pc]) * $signed(weight_mat[pk][pc]);
          end
        end
      end
    end
  end

  for (genvar pk = 0; pk < PK; pk++) begin : gen_reduce
    reduction_tree #(
      .N(PC),
      .IN_W(PROD_W),
      .ACC_W(ACC_W)
    ) u_reduction_tree (
      .clk(clk),
      .rst_n(rst_n),
      .in_vec(products_q[pk]),
      .valid_in(products_valid_q),
      .sum_out(dot_vec[pk]),
      .valid_out(reduce_valid[pk])
    );
  end

  assign valid_out = reduce_valid[0];

endmodule
