`timescale 1ns/1ps

module parallel_bias_add #(
  parameter int PK     = 8,
  parameter int ACC_W  = 32,
  parameter int BIAS_W = 32
)(
  input  logic signed [ACC_W-1:0]  psum_in [PK],
  input  logic signed [BIAS_W-1:0] bias_in [PK],
  input  logic                     bias_enable,
  input  logic [PK-1:0]            lane_mask,
  output logic signed [ACC_W-1:0]  acc_out [PK]
);

  function automatic logic signed [ACC_W-1:0] extend_bias(
    input logic signed [BIAS_W-1:0] value
  );
    begin
      return value;
    end
  endfunction

  always_comb begin
    for (int pk = 0; pk < PK; pk++) begin
      if (!lane_mask[pk]) begin
        acc_out[pk] = '0;
      end else if (bias_enable) begin
        acc_out[pk] = psum_in[pk] + extend_bias(bias_in[pk]);
      end else begin
        acc_out[pk] = psum_in[pk];
      end
    end
  end

endmodule
