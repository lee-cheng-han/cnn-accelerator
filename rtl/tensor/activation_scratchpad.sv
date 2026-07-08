`timescale 1ns/1ps

module activation_scratchpad #(
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

  logic signed [DATA_W-1:0] mem [DEPTH];
  logic [ADDR_W-1:0] write_addr;
  logic [ADDR_W-1:0] read_base_addr;
  logic [ADDR_W-1:0] debug_addr;

  assign write_addr    = (write_pixel * ADDR_W'(MAX_C)) + ADDR_W'(write_channel);
  assign read_base_addr = read_pixel * ADDR_W'(MAX_C);
  assign debug_addr    = (debug_read_pixel * ADDR_W'(MAX_C)) + ADDR_W'(debug_read_channel);

  always_ff @(posedge clk) begin
    if (write_enable && (write_addr < ADDR_W'(DEPTH))) begin
      mem[write_addr] <= write_data;
    end
  end

  always_comb begin
    for (int pc = 0; pc < PC; pc++) begin
      if (lane_mask[pc] &&
          ((read_base_addr + ADDR_W'(read_c_base + COUNT_W'(pc))) < ADDR_W'(DEPTH))) begin
        lane_data[pc] = mem[read_base_addr + ADDR_W'(read_c_base + COUNT_W'(pc))];
      end else begin
        lane_data[pc] = '0;
      end
    end

    if (debug_addr < ADDR_W'(DEPTH)) begin
      debug_read_data = mem[debug_addr];
    end else begin
      debug_read_data = '0;
    end
  end

endmodule
