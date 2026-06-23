`timescale 1ns/1ps
module output_saturate #(
  parameter int ACC_WIDTH = 32,
  parameter int OUT_WIDTH = 8
)(
  input  logic signed [ACC_WIDTH-1:0] acc_in,
  output logic signed [OUT_WIDTH-1:0] out_data
);
  localparam logic signed [ACC_WIDTH-1:0] MAX_VAL = (1 <<< (OUT_WIDTH-1)) - 1;
  localparam logic signed [ACC_WIDTH-1:0] MIN_VAL = -(1 <<< (OUT_WIDTH-1));
  always_comb begin
    if      (acc_in > MAX_VAL) out_data = MAX_VAL[OUT_WIDTH-1:0];
    else if (acc_in < MIN_VAL) out_data = MIN_VAL[OUT_WIDTH-1:0];
    else                       out_data = acc_in[OUT_WIDTH-1:0];
  end
endmodule
