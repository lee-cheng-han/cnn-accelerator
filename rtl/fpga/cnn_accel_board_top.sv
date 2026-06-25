`timescale 1ns/1ps

module cnn_accel_board_top #(
  parameter int CLK_FREQ_HZ = 100_000_000,
  parameter int BAUD_RATE   = 115200
)(
  input  logic clk,
  input  logic rst_n,

  input  logic uart_rx,
  output logic uart_tx,

  output logic led_busy,
  output logic led_done,
  output logic led_error
);

  logic [7:0] rx_data;
  logic       rx_valid;
  logic       rx_framing_error;

  logic [7:0] tx_data;
  logic       tx_valid;
  logic       tx_ready;
  logic       tx_busy;

  logic [7:0] pending_byte;
  logic       pending_valid;

  logic [31:0] heartbeat;
  logic [31:0] bytes_echoed;

  uart_rx #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD_RATE(BAUD_RATE)
  ) u_uart_rx (
    .clk(clk),
    .rst_n(rst_n),
    .rx(uart_rx),
    .data_out(rx_data),
    .data_valid(rx_valid),
    .framing_error(rx_framing_error)
  );

  uart_tx #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD_RATE(BAUD_RATE)
  ) u_uart_tx (
    .clk(clk),
    .rst_n(rst_n),
    .data_in(tx_data),
    .data_valid(tx_valid),
    .data_ready(tx_ready),
    .tx(uart_tx),
    .busy(tx_busy)
  );

  assign tx_data  = pending_byte;
  assign tx_valid = pending_valid && tx_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pending_byte  <= 8'd0;
      pending_valid <= 1'b0;
      heartbeat     <= 32'd0;
      bytes_echoed  <= 32'd0;
    end else begin
      heartbeat <= heartbeat + 32'd1;

      // Capture received byte into a one-byte holding register.
      // For this first loopback demo, the PC should send slowly enough that
      // one-byte buffering is fine.
      if (rx_valid) begin
        pending_byte  <= rx_data;
        pending_valid <= 1'b1;
      end

      // Once TX accepts the byte, clear pending.
      if (pending_valid && tx_ready) begin
        pending_valid <= 1'b0;
        bytes_echoed  <= bytes_echoed + 32'd1;
      end
    end
  end

  assign led_busy  = tx_busy;
  assign led_done  = bytes_echoed[0];
  assign led_error = rx_framing_error;

endmodule
