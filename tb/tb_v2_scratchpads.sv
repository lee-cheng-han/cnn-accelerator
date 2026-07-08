`timescale 1ns/1ps

module tb_v2_scratchpads;

  localparam int PC         = 4;
  localparam int PK         = 8;
  localparam int MAX_PIXELS = 16;
  localparam int MAX_CIN    = 16;
  localparam int MAX_COUT   = 16;
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
  logic signed [DATA_W-1:0] weight_debug_data;

  int tests;

  activation_scratchpad #(
    .PC(PC),
    .MAX_PIXELS(MAX_PIXELS),
    .MAX_C(MAX_CIN),
    .DATA_W(DATA_W)
  ) u_activation_scratchpad (
    .clk(clk),
    .write_enable(act_we),
    .write_pixel(act_wr_pixel),
    .write_channel(act_wr_channel),
    .write_data(act_wr_data),
    .read_pixel(act_read_pixel),
    .read_c_base(act_read_c_base),
    .lane_mask(act_lane_mask),
    .lane_data(act_lane_data),
    .debug_read_pixel(act_read_pixel),
    .debug_read_channel(act_read_c_base),
    .debug_read_data(act_debug_data)
  );

  weight_scratchpad #(
    .PC(PC),
    .PK(PK),
    .MAX_CIN(MAX_CIN),
    .MAX_COUT(MAX_COUT),
    .DATA_W(DATA_W)
  ) u_weight_scratchpad (
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
    .debug_out_channel(weight_read_k_base),
    .debug_in_channel(weight_read_c_base),
    .debug_kernel_idx(weight_read_k),
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
      @(posedge clk);
      @(negedge clk);
      act_we = 1'b0;
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
      @(posedge clk);
      @(negedge clk);
      weight_we = 1'b0;
    end
  endtask

  task automatic expect_act_lane(input int lane, input int value);
    begin
      if (act_lane_data[lane] !== value[DATA_W-1:0]) begin
        $display("[FAIL] activation lane %0d expected=%0d got=%0d",
                 lane, value, act_lane_data[lane]);
        $finish;
      end
      tests++;
    end
  endtask

  task automatic expect_weight(input int pk, input int pc, input int value);
    begin
      if (weight_mat[pk][pc] !== value[DATA_W-1:0]) begin
        $display("[FAIL] weight[%0d][%0d] expected=%0d got=%0d",
                 pk, pc, value, weight_mat[pk][pc]);
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
    tests = 0;

    repeat (2) @(posedge clk);

    write_activation(3, 4, 11);
    write_activation(3, 5, -7);
    write_activation(3, 6, 19);
    write_activation(3, 7, -21);

    act_read_pixel = 32'd3;
    act_read_c_base = 8'd4;
    act_lane_mask = 4'b1011;
    #1;

    expect_act_lane(0, 11);
    expect_act_lane(1, -7);
    expect_act_lane(2, 0);
    expect_act_lane(3, -21);

    act_read_pixel = 32'd99;
    act_read_c_base = 8'd0;
    act_lane_mask = 4'b1111;
    #1;
    expect_act_lane(0, 0);

    write_weight(8, 4, 5, 31);
    write_weight(8, 5, 5, -12);
    write_weight(9, 4, 5, 7);
    write_weight(15, 7, 5, -33);

    weight_read_k_base = 8'd8;
    weight_read_c_base = 8'd4;
    weight_read_k = 4'd5;
    weight_out_mask = 8'b1000_0011;
    weight_in_mask = 4'b1011;
    #1;

    expect_weight(0, 0, 31);
    expect_weight(0, 1, -12);
    expect_weight(0, 2, 0);
    expect_weight(1, 0, 7);
    expect_weight(7, 3, -33);
    expect_weight(2, 0, 0);

    weight_read_k = 4'd12;
    #1;
    expect_weight(0, 0, 0);

    $display("[PASS] tb_v2_scratchpads tests=%0d", tests);
    $finish;
  end

endmodule
