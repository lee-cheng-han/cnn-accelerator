`timescale 1ns/1ps

module tb_v2_banked_scratchpads;

  localparam int PC         = 4;
  localparam int PK         = 4;
  localparam int MAX_PIXELS = 16;
  localparam int MAX_CIN    = 10;
  localparam int MAX_COUT   = 9;
  localparam int DATA_W     = 8;

  logic clk;

  logic act_we;
  logic [31:0] act_wr_pixel;
  logic [7:0] act_wr_channel;
  logic signed [DATA_W-1:0] act_wr_data;
  logic [31:0] act_read_pixel;
  logic [7:0] act_read_c_base;
  logic [PC-1:0] act_lane_mask;
  logic signed [DATA_W-1:0] act_lane_data [PC];
  logic [31:0] act_debug_pixel;
  logic [7:0] act_debug_channel;
  logic signed [DATA_W-1:0] act_debug_data;

  logic weight_we;
  logic [7:0] weight_wr_oc;
  logic [7:0] weight_wr_ic;
  logic [3:0] weight_wr_k;
  logic signed [DATA_W-1:0] weight_wr_data;
  logic [7:0] weight_read_k_base;
  logic [7:0] weight_read_c_base;
  logic [3:0] weight_read_k;
  logic [PK-1:0] weight_out_mask;
  logic [PC-1:0] weight_in_mask;
  logic signed [DATA_W-1:0] weight_mat [PK][PC];
  logic [7:0] weight_debug_oc;
  logic [7:0] weight_debug_ic;
  logic [3:0] weight_debug_k;
  logic signed [DATA_W-1:0] weight_debug_data;

  int tests;

  banked_activation_scratchpad #(
    .PC(PC),
    .MAX_PIXELS(MAX_PIXELS),
    .MAX_C(MAX_CIN),
    .DATA_W(DATA_W)
  ) u_banked_activation_scratchpad (
    .clk(clk),
    .write_enable(act_we),
    .write_pixel(act_wr_pixel),
    .write_channel(act_wr_channel),
    .write_data(act_wr_data),
    .read_pixel(act_read_pixel),
    .read_c_base(act_read_c_base),
    .lane_mask(act_lane_mask),
    .lane_data(act_lane_data),
    .debug_read_pixel(act_debug_pixel),
    .debug_read_channel(act_debug_channel),
    .debug_read_data(act_debug_data)
  );

  banked_weight_scratchpad #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .DATA_W(DATA_W)
  ) u_banked_weight_scratchpad (
    .clk(clk),
    .write_enable(weight_we),
    .write_out_channel(weight_wr_oc),
    .write_in_channel(weight_wr_ic),
    .write_kernel_idx(weight_wr_k),
    .write_data(weight_wr_data),
    .read_k_base(weight_read_k_base),
    .read_c_base(weight_read_c_base),
    .read_kernel_idx(weight_read_k),
    .out_lane_mask(weight_out_mask),
    .in_lane_mask(weight_in_mask),
    .weight_mat(weight_mat),
    .debug_out_channel(weight_debug_oc),
    .debug_in_channel(weight_debug_ic),
    .debug_kernel_idx(weight_debug_k),
    .debug_read_data(weight_debug_data)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task automatic write_activation(input int pixel, input int channel, input int value);
    begin
      @(negedge clk);
      act_wr_pixel = pixel[31:0];
      act_wr_channel = channel[7:0];
      act_wr_data = value[DATA_W-1:0];
      act_we = 1'b1;
      @(negedge clk);
      act_we = 1'b0;
    end
  endtask

  task automatic request_activation(input int pixel, input int channel_base, input logic [PC-1:0] mask);
    begin
      @(negedge clk);
      act_read_pixel = pixel[31:0];
      act_read_c_base = channel_base[7:0];
      act_lane_mask = mask;
      @(posedge clk);
      #1;
    end
  endtask

  task automatic request_activation_debug(input int pixel, input int channel);
    begin
      @(negedge clk);
      act_debug_pixel = pixel[31:0];
      act_debug_channel = channel[7:0];
      @(posedge clk);
      #1;
    end
  endtask

  task automatic write_weight(input int oc, input int ic, input int k, input int value);
    begin
      @(negedge clk);
      weight_wr_oc = oc[7:0];
      weight_wr_ic = ic[7:0];
      weight_wr_k = k[3:0];
      weight_wr_data = value[DATA_W-1:0];
      weight_we = 1'b1;
      @(negedge clk);
      weight_we = 1'b0;
    end
  endtask

  task automatic request_weight(
    input int oc_base,
    input int ic_base,
    input int kernel,
    input logic [PK-1:0] out_mask,
    input logic [PC-1:0] in_mask
  );
    begin
      @(negedge clk);
      weight_read_k_base = oc_base[7:0];
      weight_read_c_base = ic_base[7:0];
      weight_read_k = kernel[3:0];
      weight_out_mask = out_mask;
      weight_in_mask = in_mask;
      @(posedge clk);
      #1;
    end
  endtask

  task automatic request_weight_debug(input int oc, input int ic, input int kernel);
    begin
      @(negedge clk);
      weight_debug_oc = oc[7:0];
      weight_debug_ic = ic[7:0];
      weight_debug_k = kernel[3:0];
      @(posedge clk);
      #1;
    end
  endtask

  task automatic expect_s8(input string name, input logic signed [DATA_W-1:0] got, input int expected);
    logic signed [DATA_W-1:0] exp_s8;
    begin
      exp_s8 = expected[DATA_W-1:0];
      if (got !== exp_s8) begin
        $display("[FAIL] %s expected=%0d got=%0d", name, exp_s8, got);
        $finish;
      end
      tests++;
    end
  endtask

  initial begin
    act_we = 1'b0;
    act_wr_pixel = '0;
    act_wr_channel = '0;
    act_wr_data = '0;
    act_read_pixel = '0;
    act_read_c_base = '0;
    act_lane_mask = '0;
    act_debug_pixel = '0;
    act_debug_channel = '0;

    weight_we = 1'b0;
    weight_wr_oc = '0;
    weight_wr_ic = '0;
    weight_wr_k = '0;
    weight_wr_data = '0;
    weight_read_k_base = '0;
    weight_read_c_base = '0;
    weight_read_k = '0;
    weight_out_mask = '0;
    weight_in_mask = '0;
    weight_debug_oc = '0;
    weight_debug_ic = '0;
    weight_debug_k = '0;
    tests = 0;

    repeat (3) @(posedge clk);

    write_activation(2, 1, 11);
    write_activation(2, 2, -12);
    write_activation(2, 3, 13);
    write_activation(2, 4, -14);
    write_activation(2, 8, 88);
    write_activation(2, 9, 0);

    request_activation(2, 1, 4'b1111);
    expect_s8("activation unaligned lane0", act_lane_data[0], 11);
    expect_s8("activation unaligned lane1", act_lane_data[1], -12);
    expect_s8("activation unaligned lane2", act_lane_data[2], 13);
    expect_s8("activation unaligned lane3", act_lane_data[3], -14);

    request_activation(2, 8, 4'b0111);
    expect_s8("activation tail valid", act_lane_data[0], 88);
    expect_s8("activation tail unwritten", act_lane_data[1], 0);
    expect_s8("activation tail out of range", act_lane_data[2], 0);
    expect_s8("activation masked lane", act_lane_data[3], 0);

    request_activation_debug(2, 4);
    expect_s8("activation debug", act_debug_data, -14);

    request_activation(99, 0, 4'b1111);
    expect_s8("activation pixel out of range", act_lane_data[0], 0);

    write_weight(1, 1, 2, 21);
    write_weight(1, 2, 2, -22);
    write_weight(2, 1, 2, 23);
    write_weight(3, 3, 2, 0);
    write_weight(4, 4, 7, -44);
    write_weight(8, 8, 2, 88);

    request_weight(1, 1, 2, 4'b1111, 4'b1111);
    expect_s8("weight unaligned 0,0", weight_mat[0][0], 21);
    expect_s8("weight unaligned 0,1", weight_mat[0][1], -22);
    expect_s8("weight unaligned 1,0", weight_mat[1][0], 23);
    expect_s8("weight unwritten", weight_mat[2][2], 0);

    request_weight(4, 4, 7, 4'b0001, 4'b0001);
    expect_s8("weight banked higher block", weight_mat[0][0], -44);
    expect_s8("weight masked output", weight_mat[1][0], 0);
    expect_s8("weight masked input", weight_mat[0][1], 0);

    request_weight(8, 8, 2, 4'b1111, 4'b1111);
    expect_s8("weight tail valid", weight_mat[0][0], 88);
    expect_s8("weight output out of range", weight_mat[1][0], 0);
    expect_s8("weight input out of range", weight_mat[0][2], 0);

    request_weight_debug(4, 4, 7);
    expect_s8("weight debug", weight_debug_data, -44);

    request_weight(1, 1, 12, 4'b1111, 4'b1111);
    expect_s8("weight kernel out of range", weight_mat[0][0], 0);

    $display("[PASS] tb_v2_banked_scratchpads tests=%0d", tests);
    $finish;
  end

endmodule
