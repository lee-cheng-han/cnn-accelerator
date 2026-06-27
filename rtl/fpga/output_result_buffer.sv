`timescale 1ns/1ps

module output_result_buffer #(
  parameter int DATA_WIDTH = 8,
  parameter int DEPTH      = 16384
)(
  input  logic clk,
  input  logic rst_n,
  input  logic clear,

  input  logic signed [DATA_WIDTH-1:0] wr_data,
  input  logic                         wr_valid,
  input  logic                         wr_last,
  output logic                         wr_ready,

  output logic signed [DATA_WIDTH-1:0] rd_data,
  output logic                         rd_valid,
  output logic                         rd_last,
  input  logic                         rd_ready,

  output logic                         full,
  output logic                         empty,
  output logic                         done,

  output logic [$clog2(DEPTH+1)-1:0]   write_count,
  output logic [$clog2(DEPTH+1)-1:0]   read_count,
  output logic [$clog2(DEPTH+1)-1:0]   stored_count
);

  localparam int ADDR_W = $clog2(DEPTH);

  // Store {last_bit, data} together so Vivado infers one BRAM-backed RAM.
  (* ram_style = "block" *)
  logic [DATA_WIDTH:0] ram [0:DEPTH-1];

  logic [ADDR_W-1:0] wr_ptr;
  logic [ADDR_W-1:0] rd_ptr;

  logic signed [DATA_WIDTH-1:0] rd_data_q;
  logic                         rd_last_q;
  logic                         rd_valid_q;

  logic wr_fire;
  logic rd_fire;
  logic rd_request;

  assign full  = (stored_count == DEPTH);
  assign empty = (stored_count == 0);

  assign wr_ready = !full;
  assign wr_fire  = wr_valid && wr_ready;

  assign rd_fire    = rd_valid_q && rd_ready;
  assign rd_request = !empty && (!rd_valid_q || rd_fire);

  assign rd_data  = rd_data_q;
  assign rd_last  = rd_last_q;
  assign rd_valid = rd_valid_q;

  // Important for BRAM inference:
  // This is clock-only. No async reset on RAM.
  always_ff @(posedge clk) begin
    if (wr_fire) begin
      ram[wr_ptr] <= {wr_last, wr_data};
    end

    if (rd_request) begin
      {rd_last_q, rd_data_q} <= ram[rd_ptr];
    end
  end

  // Control/state logic. Synchronous reset style keeps RAM inference clean.
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wr_ptr       <= '0;
      rd_ptr       <= '0;
      rd_valid_q   <= 1'b0;
      done         <= 1'b0;
      write_count  <= '0;
      read_count   <= '0;
      stored_count <= '0;
    end else if (clear) begin
      wr_ptr       <= '0;
      rd_ptr       <= '0;
      rd_valid_q   <= 1'b0;
      done         <= 1'b0;
      write_count  <= '0;
      read_count   <= '0;
      stored_count <= '0;
    end else begin
      if (wr_fire) begin
        wr_ptr <= wr_ptr + 1'b1;
        write_count <= write_count + 1'b1;

        if (wr_last) begin
          done <= 1'b1;
        end
      end

      if (rd_request) begin
        rd_ptr <= rd_ptr + 1'b1;
        rd_valid_q <= 1'b1;
      end else if (rd_fire) begin
        rd_valid_q <= 1'b0;
      end

      if (rd_fire) begin
        read_count <= read_count + 1'b1;
      end

      unique case ({wr_fire, rd_fire})
        2'b10: stored_count <= stored_count + 1'b1;
        2'b01: stored_count <= stored_count - 1'b1;
        default: stored_count <= stored_count;
      endcase

      if (rd_fire && rd_last_q) begin
        done <= 1'b0;
      end
    end
  end

endmodule
