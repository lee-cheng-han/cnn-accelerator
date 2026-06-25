`timescale 1ns/1ps

module uart_result_sender #(
  parameter int DATA_WIDTH = 8
)(
  input  logic clk,
  input  logic rst_n,
  input  logic clear,

  // Pulse from command decoder when PC sends R
  input  logic start,

  // Read side from output_result_buffer
  input  logic signed [DATA_WIDTH-1:0] buf_rd_data,
  input  logic                         buf_rd_valid,
  input  logic                         buf_rd_last,
  output logic                         buf_rd_ready,

  // Output side to UART TX wrapper/path
  output logic [7:0] tx_data,
  output logic       tx_valid,
  input  logic       tx_ready,

  output logic       busy,
  output logic       done,
  output logic [31:0] bytes_sent
);

  logic active;

  logic [7:0] tx_data_q;
  logic       tx_valid_q;
  logic       tx_last_q;

  logic buf_accept;
  logic tx_fire;

  assign tx_data  = tx_data_q;
  assign tx_valid = tx_valid_q;

  assign busy = active || tx_valid_q;

  assign tx_fire = tx_valid_q && tx_ready;

  // Pull a new byte only when our one-byte TX staging register is empty.
  assign buf_accept   = active && buf_rd_valid && !tx_valid_q;
  assign buf_rd_ready = active && !tx_valid_q;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      active     <= 1'b0;
      tx_data_q  <= 8'd0;
      tx_valid_q <= 1'b0;
      tx_last_q  <= 1'b0;
      done       <= 1'b0;
      bytes_sent <= 32'd0;
    end else begin
      done <= 1'b0;

      if (clear) begin
        active     <= 1'b0;
        tx_data_q  <= 8'd0;
        tx_valid_q <= 1'b0;
        tx_last_q  <= 1'b0;
        done       <= 1'b0;
        bytes_sent <= 32'd0;
      end else begin
        if (start && !active && !tx_valid_q) begin
          active <= 1'b1;
          bytes_sent <= 32'd0;
        end

        if (buf_accept) begin
          tx_data_q  <= buf_rd_data;
          tx_last_q  <= buf_rd_last;
          tx_valid_q <= 1'b1;
        end else if (tx_fire) begin
          tx_valid_q <= 1'b0;
        end

        if (tx_fire) begin
          bytes_sent <= bytes_sent + 32'd1;

          if (tx_last_q) begin
            active <= 1'b0;
            done <= 1'b1;
          end
        end
      end
    end
  end

endmodule
