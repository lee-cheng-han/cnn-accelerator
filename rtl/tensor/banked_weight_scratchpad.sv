`timescale 1ns/1ps

module banked_weight_scratchpad #(
  parameter int PC       = 4,
  parameter int PK       = 8,
  parameter int MAX_CIN  = 64,
  parameter int MAX_COUT = 64,
  parameter int DATA_W   = 8,
  parameter int COUNT_W  = 8,
  parameter int ADDR_W   = 32
)(
  input  logic clk,

  input  logic write_enable,
  input  logic [COUNT_W-1:0] write_out_channel,
  input  logic [COUNT_W-1:0] write_in_channel,
  input  logic [3:0] write_kernel_idx,
  input  logic signed [DATA_W-1:0] write_data,

  input  logic [COUNT_W-1:0] read_k_base,
  input  logic [COUNT_W-1:0] read_c_base,
  input  logic [3:0] read_kernel_idx,
  input  logic [PK-1:0] out_lane_mask,
  input  logic [PC-1:0] in_lane_mask,
  output logic signed [DATA_W-1:0] weight_mat [PK][PC],

  input  logic [COUNT_W-1:0] debug_out_channel,
  input  logic [COUNT_W-1:0] debug_in_channel,
  input  logic [3:0] debug_kernel_idx,
  output logic signed [DATA_W-1:0] debug_read_data
);

  localparam int DEPTH = MAX_COUT * MAX_CIN * 9;

  logic signed [DATA_W-1:0] lane_mem [PK][PC][0:DEPTH-1];
  logic signed [DATA_W-1:0] weight_mat_q [PK][PC];
  logic signed [DATA_W-1:0] debug_read_data_q;

  assign weight_mat = weight_mat_q;
  assign debug_read_data = debug_read_data_q;

  function automatic logic [ADDR_W-1:0] packed_addr(
    input logic [COUNT_W-1:0] out_channel,
    input logic [COUNT_W-1:0] in_channel,
    input logic [3:0] kernel_idx
  );
    begin
      packed_addr =
        (((ADDR_W'(out_channel) * ADDR_W'(MAX_CIN)) + ADDR_W'(in_channel)) *
         ADDR_W'(9)) + ADDR_W'(kernel_idx);
    end
  endfunction

  always_ff @(posedge clk) begin
    logic [ADDR_W-1:0] write_addr;
    logic [ADDR_W-1:0] debug_addr;

    write_addr = packed_addr(write_out_channel, write_in_channel, write_kernel_idx);
    if (write_enable &&
        (write_out_channel < COUNT_W'(MAX_COUT)) &&
        (write_in_channel < COUNT_W'(MAX_CIN)) &&
        (write_kernel_idx < 4'd9) &&
        (write_addr < ADDR_W'(DEPTH))) begin
      for (int pk = 0; pk < PK; pk++) begin
        for (int pc = 0; pc < PC; pc++) begin
          lane_mem[pk][pc][write_addr] <= write_data;
        end
      end
    end

    for (int pk = 0; pk < PK; pk++) begin
      for (int pc = 0; pc < PC; pc++) begin
        logic [COUNT_W-1:0] out_channel;
        logic [COUNT_W-1:0] in_channel;
        logic [ADDR_W-1:0] read_addr;

        out_channel = read_k_base + COUNT_W'(pk);
        in_channel = read_c_base + COUNT_W'(pc);
        read_addr = packed_addr(out_channel, in_channel, read_kernel_idx);
        if (out_lane_mask[pk] &&
            in_lane_mask[pc] &&
            (out_channel < COUNT_W'(MAX_COUT)) &&
            (in_channel < COUNT_W'(MAX_CIN)) &&
            (read_kernel_idx < 4'd9) &&
            (read_addr < ADDR_W'(DEPTH))) begin
          weight_mat_q[pk][pc] <= lane_mem[pk][pc][read_addr];
        end else begin
          weight_mat_q[pk][pc] <= '0;
        end
      end
    end

    debug_addr =
      packed_addr(debug_out_channel, debug_in_channel, debug_kernel_idx);
    if ((debug_out_channel < COUNT_W'(MAX_COUT)) &&
        (debug_in_channel < COUNT_W'(MAX_CIN)) &&
        (debug_kernel_idx < 4'd9) &&
        (debug_addr < ADDR_W'(DEPTH))) begin
      debug_read_data_q <= lane_mem[0][0][debug_addr];
    end else begin
      debug_read_data_q <= '0;
    end
  end

endmodule
