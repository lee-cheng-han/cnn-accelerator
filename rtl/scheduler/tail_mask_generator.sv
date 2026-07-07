`timescale 1ns/1ps

module tail_mask_generator #(
  parameter int LANES   = 8,
  parameter int COUNT_W = 8
)(
  input  logic [COUNT_W-1:0] base,
  input  logic [COUNT_W-1:0] count,
  output logic [LANES-1:0]   lane_mask
);

  always_comb begin
    for (int lane = 0; lane < LANES; lane++) begin
      lane_mask[lane] = ((base + COUNT_W'(lane)) < count);
    end
  end

endmodule
