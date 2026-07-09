`timescale 1ns/1ps

module ping_pong_activation_scratchpad #(
  parameter int PC         = 4,
  parameter int MAX_PIXELS = 4096,
  parameter int MAX_C      = 64,
  parameter int DATA_W     = 8,
  parameter int DIM_W      = 16,
  parameter int COUNT_W    = 8,
  parameter int ADDR_W     = 32
)(
  input  logic clk,

  input  logic write_bank,
  input  logic write_enable,
  input  logic [ADDR_W-1:0] write_pixel,
  input  logic [COUNT_W-1:0] write_channel,
  input  logic signed [DATA_W-1:0] write_data,

  input  logic read_bank,
  input  logic [ADDR_W-1:0] read_pixel,
  input  logic [COUNT_W-1:0] read_c_base,
  input  logic [PC-1:0] lane_mask,
  output logic signed [DATA_W-1:0] lane_data [PC],

  input  logic debug_bank,
  input  logic [ADDR_W-1:0] debug_read_pixel,
  input  logic [COUNT_W-1:0] debug_read_channel,
  output logic signed [DATA_W-1:0] debug_read_data
);

  logic signed [DATA_W-1:0] bank0_lane_data [PC];
  logic signed [DATA_W-1:0] bank1_lane_data [PC];
  logic signed [DATA_W-1:0] bank0_debug_data;
  logic signed [DATA_W-1:0] bank1_debug_data;

  activation_scratchpad #(
    .PC(PC),
    .MAX_PIXELS(MAX_PIXELS),
    .MAX_C(MAX_C),
    .DATA_W(DATA_W),
    .DIM_W(DIM_W),
    .COUNT_W(COUNT_W),
    .ADDR_W(ADDR_W)
  ) u_bank0 (
    .clk(clk),
    .write_enable(write_enable && (write_bank == 1'b0)),
    .write_pixel(write_pixel),
    .write_channel(write_channel),
    .write_data(write_data),
    .read_pixel(read_pixel),
    .read_c_base(read_c_base),
    .lane_mask(lane_mask),
    .lane_data(bank0_lane_data),
    .debug_read_pixel(debug_read_pixel),
    .debug_read_channel(debug_read_channel),
    .debug_read_data(bank0_debug_data)
  );

  activation_scratchpad #(
    .PC(PC),
    .MAX_PIXELS(MAX_PIXELS),
    .MAX_C(MAX_C),
    .DATA_W(DATA_W),
    .DIM_W(DIM_W),
    .COUNT_W(COUNT_W),
    .ADDR_W(ADDR_W)
  ) u_bank1 (
    .clk(clk),
    .write_enable(write_enable && (write_bank == 1'b1)),
    .write_pixel(write_pixel),
    .write_channel(write_channel),
    .write_data(write_data),
    .read_pixel(read_pixel),
    .read_c_base(read_c_base),
    .lane_mask(lane_mask),
    .lane_data(bank1_lane_data),
    .debug_read_pixel(debug_read_pixel),
    .debug_read_channel(debug_read_channel),
    .debug_read_data(bank1_debug_data)
  );

  always_comb begin
    for (int pc = 0; pc < PC; pc++) begin
      lane_data[pc] = read_bank ? bank1_lane_data[pc] : bank0_lane_data[pc];
    end

    debug_read_data = debug_bank ? bank1_debug_data : bank0_debug_data;
  end

endmodule
