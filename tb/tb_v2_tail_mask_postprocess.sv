`timescale 1ns/1ps

module tb_v2_tail_mask_postprocess;

  localparam int PK    = 8;
  localparam int ACC_W = 32;
  localparam int OUT_W = 8;

  logic [7:0] base;
  logic [7:0] count;
  logic [PK-1:0] mask;

  logic signed [ACC_W-1:0] psum [PK];
  logic signed [ACC_W-1:0] bias [PK];
  logic signed [ACC_W-1:0] after_bias [PK];
  logic signed [ACC_W-1:0] after_relu [PK];
  logic signed [ACC_W-1:0] after_quant [PK];
  logic signed [OUT_W-1:0] out_vec [PK];

  tail_mask_generator #(
    .LANES(PK),
    .COUNT_W(8)
  ) u_tail_mask (
    .base(base),
    .count(count),
    .lane_mask(mask)
  );

  parallel_bias_add #(
    .PK(PK),
    .ACC_W(ACC_W),
    .BIAS_W(ACC_W)
  ) u_bias (
    .psum_in(psum),
    .bias_in(bias),
    .bias_enable(1'b1),
    .lane_mask(mask),
    .acc_out(after_bias)
  );

  parallel_relu #(
    .PK(PK),
    .ACC_W(ACC_W)
  ) u_relu (
    .acc_in(after_bias),
    .relu_enable(1'b1),
    .lane_mask(mask),
    .acc_out(after_relu)
  );

  parallel_quantizer #(
    .PK(PK),
    .ACC_W(ACC_W)
  ) u_quant (
    .acc_in(after_relu),
    .quant_enable(1'b1),
    .quant_shift(5'd1),
    .lane_mask(mask),
    .acc_out(after_quant)
  );

  parallel_saturate #(
    .PK(PK),
    .ACC_W(ACC_W),
    .OUT_W(OUT_W)
  ) u_sat (
    .acc_in(after_quant),
    .lane_mask(mask),
    .out_vec(out_vec)
  );

  task automatic expect_mask(input logic [PK-1:0] expected);
    begin
      #1;
      if (mask !== expected) begin
        $display("[FAIL] mask expected=0x%02h got=0x%02h", expected, mask);
        $finish;
      end
    end
  endtask

  task automatic expect_out(input int lane, input int expected);
    begin
      if (out_vec[lane] !== expected[OUT_W-1:0]) begin
        $display("[FAIL] out_vec[%0d] expected=%0d got=%0d",
                 lane, expected, out_vec[lane]);
        $finish;
      end
    end
  endtask

  initial begin
    base = 8'd0;
    count = 8'd3;
    expect_mask(8'b0000_0111);

    base = 8'd8;
    count = 8'd13;
    expect_mask(8'b0001_1111);

    base = 8'd16;
    count = 8'd16;
    expect_mask(8'b0000_0000);

    base = 8'd8;
    count = 8'd13;

    for (int pk = 0; pk < PK; pk++) begin
      psum[pk] = (pk == 0) ? 32'sd260 :
                 (pk == 1) ? -32'sd20 :
                 (pk == 2) ? 32'sd60 :
                 (pk == 3) ? 32'sd400 :
                 (pk == 4) ? 32'sd16 : 32'sd1234;
      bias[pk] = (pk == 0) ? 32'sd0 :
                 (pk == 1) ? 32'sd2 :
                 (pk == 2) ? -32'sd4 :
                 (pk == 3) ? 32'sd0 :
                 (pk == 4) ? 32'sd2 : 32'sd0;
    end

    #1;
    expect_out(0, 127);
    expect_out(1, 0);
    expect_out(2, 28);
    expect_out(3, 127);
    expect_out(4, 9);
    expect_out(5, 0);
    expect_out(6, 0);
    expect_out(7, 0);

    $display("[PASS] tb_v2_tail_mask_postprocess");
    $finish;
  end

endmodule
