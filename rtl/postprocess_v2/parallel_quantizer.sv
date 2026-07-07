`timescale 1ns/1ps

module parallel_quantizer #(
  parameter int PK    = 8,
  parameter int ACC_W = 32
)(
  input  logic signed [ACC_W-1:0] acc_in [PK],
  input  logic                    quant_enable,
  input  logic [4:0]              quant_shift,
  input  logic [PK-1:0]           lane_mask,
  output logic signed [ACC_W-1:0] acc_out [PK]
);

  always_comb begin
    for (int pk = 0; pk < PK; pk++) begin
      if (!lane_mask[pk]) begin
        acc_out[pk] = '0;
      end else if (quant_enable) begin
        acc_out[pk] = acc_in[pk] >>> quant_shift;
      end else begin
        acc_out[pk] = acc_in[pk];
      end
    end
  end

endmodule
