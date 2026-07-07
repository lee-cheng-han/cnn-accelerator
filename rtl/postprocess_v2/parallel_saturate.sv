`timescale 1ns/1ps

module parallel_saturate #(
  parameter int PK    = 8,
  parameter int ACC_W = 32,
  parameter int OUT_W = 8
)(
  input  logic signed [ACC_W-1:0] acc_in [PK],
  input  logic [PK-1:0]           lane_mask,
  output logic signed [OUT_W-1:0] out_vec [PK]
);

  localparam logic signed [ACC_W-1:0] MAX_VAL = (ACC_W'(1) <<< (OUT_W - 1)) - ACC_W'(1);
  localparam logic signed [ACC_W-1:0] MIN_VAL = -(ACC_W'(1) <<< (OUT_W - 1));

  always_comb begin
    for (int pk = 0; pk < PK; pk++) begin
      if (!lane_mask[pk]) begin
        out_vec[pk] = '0;
      end else if (acc_in[pk] > MAX_VAL) begin
        out_vec[pk] = {1'b0, {(OUT_W-1){1'b1}}};
      end else if (acc_in[pk] < MIN_VAL) begin
        out_vec[pk] = {1'b1, {(OUT_W-1){1'b0}}};
      end else begin
        out_vec[pk] = acc_in[pk][OUT_W-1:0];
      end
    end
  end

endmodule
