`timescale 1ns/1ps

module residual_add #(
  parameter int PK    = 8,
  parameter int DATA_W = 8
)(
  input  logic signed [DATA_W-1:0] network_out [PK],
  input  logic signed [DATA_W-1:0] residual_in [PK],
  input  logic                     residual_enable,
  input  logic                     subtract_residual,
  input  logic [PK-1:0]            lane_mask,
  output logic signed [DATA_W-1:0] out_vec [PK]
);

  localparam logic signed [DATA_W:0] MAX_VAL = (DATA_W+1)'(1) <<< (DATA_W - 1);
  localparam logic signed [DATA_W:0] SAT_MAX = MAX_VAL - (DATA_W+1)'(1);
  localparam logic signed [DATA_W:0] SAT_MIN = -MAX_VAL;

  logic signed [DATA_W:0] combined [PK];

  always_comb begin
    for (int pk = 0; pk < PK; pk++) begin
      if (!lane_mask[pk]) begin
        combined[pk] = '0;
      end else if (!residual_enable) begin
        combined[pk] = {network_out[pk][DATA_W-1], network_out[pk]};
      end else if (subtract_residual) begin
        combined[pk] = {residual_in[pk][DATA_W-1], residual_in[pk]} -
                       {network_out[pk][DATA_W-1], network_out[pk]};
      end else begin
        combined[pk] = {residual_in[pk][DATA_W-1], residual_in[pk]} +
                       {network_out[pk][DATA_W-1], network_out[pk]};
      end

      if (combined[pk] > SAT_MAX) begin
        out_vec[pk] = {1'b0, {(DATA_W-1){1'b1}}};
      end else if (combined[pk] < SAT_MIN) begin
        out_vec[pk] = {1'b1, {(DATA_W-1){1'b0}}};
      end else begin
        out_vec[pk] = combined[pk][DATA_W-1:0];
      end
    end
  end

endmodule
