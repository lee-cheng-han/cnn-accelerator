`timescale 1ns/1ps

module banked_activation_scratchpad #(
  parameter int PC         = 4,
  parameter int MAX_PIXELS = 4096,
  parameter int MAX_C      = 64,
  parameter int DATA_W     = 8,
  parameter int DIM_W      = 16,
  parameter int COUNT_W    = 8,
  parameter int ADDR_W     = 32
)(
  input  logic clk,

  input  logic write_enable,
  input  logic [ADDR_W-1:0] write_pixel,
  input  logic [COUNT_W-1:0] write_channel,
  input  logic signed [DATA_W-1:0] write_data,

  input  logic [ADDR_W-1:0] read_pixel,
  input  logic [COUNT_W-1:0] read_c_base,
  input  logic [PC-1:0] lane_mask,
  output logic signed [DATA_W-1:0] lane_data [PC],

  input  logic [ADDR_W-1:0] debug_read_pixel,
  input  logic [COUNT_W-1:0] debug_read_channel,
  output logic signed [DATA_W-1:0] debug_read_data
);

  localparam int DEPTH = MAX_PIXELS * MAX_C;

  logic signed [DATA_W-1:0] lane_mem [PC][0:DEPTH-1];
  logic signed [DATA_W-1:0] lane_data_q [PC];
  logic signed [DATA_W-1:0] debug_read_data_q;
  logic write_valid_q = 1'b0;
  logic [ADDR_W-1:0] write_addr_q = '0;
  logic signed [DATA_W-1:0] write_data_q = '0;

  assign lane_data = lane_data_q;
  assign debug_read_data = debug_read_data_q;

  always_ff @(posedge clk) begin
    logic [ADDR_W-1:0] write_addr;
    logic [ADDR_W-1:0] debug_addr;

    write_addr = (write_pixel * ADDR_W'(MAX_C)) + ADDR_W'(write_channel);
    if (write_valid_q) begin
      for (int lane = 0; lane < PC; lane++) begin
        lane_mem[lane][write_addr_q] <= write_data_q;
      end
    end

    write_valid_q <=
      write_enable &&
      (write_pixel < ADDR_W'(MAX_PIXELS)) &&
      (write_channel < COUNT_W'(MAX_C)) &&
      (write_addr < ADDR_W'(DEPTH));
    write_addr_q <= write_addr;
    write_data_q <= write_data;

    for (int lane = 0; lane < PC; lane++) begin
      logic [COUNT_W-1:0] channel;
      logic [ADDR_W-1:0] read_addr;

      channel = read_c_base + COUNT_W'(lane);
      read_addr = (read_pixel * ADDR_W'(MAX_C)) + ADDR_W'(channel);
      if (lane_mask[lane] &&
          (read_pixel < ADDR_W'(MAX_PIXELS)) &&
          (channel < COUNT_W'(MAX_C)) &&
          (read_addr < ADDR_W'(DEPTH))) begin
        lane_data_q[lane] <= lane_mem[lane][read_addr];
      end else begin
        lane_data_q[lane] <= '0;
      end
    end

    debug_addr =
      (debug_read_pixel * ADDR_W'(MAX_C)) + ADDR_W'(debug_read_channel);
    if ((debug_read_pixel < ADDR_W'(MAX_PIXELS)) &&
        (debug_read_channel < COUNT_W'(MAX_C)) &&
        (debug_addr < ADDR_W'(DEPTH))) begin
      debug_read_data_q <= lane_mem[0][debug_addr];
    end else begin
      debug_read_data_q <= '0;
    end
  end

endmodule
