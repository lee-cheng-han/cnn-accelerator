`timescale 1ns/1ps

module tb_v2_psum_accumulator;

  localparam int PK    = 8;
  localparam int ACC_W = 32;

  logic clk;
  logic rst_n;
  logic clear;
  logic accumulate;
  logic [PK-1:0] lane_mask;
  logic signed [ACC_W-1:0] add_vec [PK];
  logic signed [ACC_W-1:0] psum_vec [PK];

  psum_accumulator #(
    .PK(PK),
    .ACC_W(ACC_W)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),
    .accumulate(accumulate),
    .lane_mask(lane_mask),
    .add_vec(add_vec),
    .psum_vec(psum_vec)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task automatic check_lane(input int lane, input int expected);
    begin
      if (psum_vec[lane] !== expected) begin
        $display("[FAIL] lane %0d expected=%0d got=%0d",
                 lane, expected, psum_vec[lane]);
        $finish;
      end
    end
  endtask

  initial begin
    rst_n      = 1'b0;
    clear      = 1'b0;
    accumulate = 1'b0;
    lane_mask  = '0;

    for (int pk = 0; pk < PK; pk++) begin
      add_vec[pk] = '0;
    end

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    for (int pk = 0; pk < PK; pk++) begin
      add_vec[pk] = pk + 1;
    end

    lane_mask  = 8'hff;
    accumulate = 1'b1;
    @(posedge clk);
    accumulate = 1'b0;

    for (int pk = 0; pk < PK; pk++) begin
      check_lane(pk, pk + 1);
    end

    for (int pk = 0; pk < PK; pk++) begin
      add_vec[pk] = -2 * (pk + 1);
    end

    lane_mask  = 8'b0101_0101;
    accumulate = 1'b1;
    @(posedge clk);
    accumulate = 1'b0;

    check_lane(0, -1);
    check_lane(1, 2);
    check_lane(2, -3);
    check_lane(3, 4);
    check_lane(4, -5);
    check_lane(5, 6);
    check_lane(6, -7);
    check_lane(7, 8);

    clear = 1'b1;
    @(posedge clk);
    clear = 1'b0;

    for (int pk = 0; pk < PK; pk++) begin
      check_lane(pk, 0);
    end

    $display("[PASS] tb_v2_psum_accumulator");
    $finish;
  end

endmodule
