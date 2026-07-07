`timescale 1ns/1ps

module tensor_address_gen #(
  parameter int DIM_W = 16,
  parameter int ADDR_W = 32
)(
  input  logic [DIM_W-1:0] input_width,
  input  logic [DIM_W-1:0] input_height,
  input  logic [DIM_W-1:0] out_x,
  input  logic [DIM_W-1:0] out_y,
  input  logic [1:0]       kernel_x,
  input  logic [1:0]       kernel_y,
  input  logic [1:0]       stride,
  input  logic [1:0]       padding,

  output logic             valid,
  output logic [ADDR_W-1:0] pixel_index
);

  logic signed [DIM_W:0] in_x;
  logic signed [DIM_W:0] in_y;

  always_comb begin
    in_x = $signed({1'b0, out_x}) * $signed({1'b0, stride}) +
           $signed({{(DIM_W-1){1'b0}}, kernel_x}) -
           $signed({{(DIM_W-1){1'b0}}, padding});

    in_y = $signed({1'b0, out_y}) * $signed({1'b0, stride}) +
           $signed({{(DIM_W-1){1'b0}}, kernel_y}) -
           $signed({{(DIM_W-1){1'b0}}, padding});

    valid = (in_x >= 0) &&
            (in_y >= 0) &&
            (in_x < $signed({1'b0, input_width})) &&
            (in_y < $signed({1'b0, input_height}));

    if (valid) begin
      pixel_index = ADDR_W'(in_y[DIM_W-1:0]) * ADDR_W'(input_width) +
                    ADDR_W'(in_x[DIM_W-1:0]);
    end else begin
      pixel_index = '0;
    end
  end

endmodule
