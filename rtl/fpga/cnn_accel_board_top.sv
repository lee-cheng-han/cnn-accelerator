`timescale 1ns/1ps

module cnn_accel_board_top #(
  parameter int CLK_FREQ_HZ  = 100_000_000,
  parameter int BAUD_RATE    = 115200,
  parameter int RESULT_DEPTH = 16384
)(
  input  logic clk,
  input  logic rst_n,

  input  logic uart_rx,
  output logic uart_tx,

  output logic led_busy,
  output logic led_done,
  output logic led_error
);

  // UART RX signals
  logic [7:0] rx_data;
  logic       rx_valid;
  logic       rx_framing_error;

  // UART TX signals
  logic [7:0] tx_data;
  logic       tx_valid;
  logic       tx_ready;
  logic       tx_busy;

  // Command decoder outputs
  logic ping_valid;
  logic read_request_valid;

  logic cfg_valid;
  logic [15:0] cfg_width;
  logic [15:0] cfg_height;
  logic cfg_kernel_mode;
  logic cfg_relu_enable;
  logic cfg_bias_enable;
  logic cfg_quant_enable;
  logic [4:0] cfg_quant_shift;

  logic weight_valid;
  logic [7:0] weight_index;
  logic signed [7:0] weight_data;
  logic weights_done;

  logic bias_valid;
  logic [1:0] bias_index;
  logic signed [31:0] bias_data;
  logic bias_done;

  logic pixel_valid;
  logic [31:0] pixel_index;
  logic signed [7:0] pixel_data;
  logic [31:0] image_length;
  logic image_done;

  logic protocol_error;

  // System core status
  logic pixel_ready;

  logic config_loaded;
  logic weights_loaded;
  logic bias_loaded;
  logic system_ready;

  logic result_buffer_full;
  logic result_buffer_empty;
  logic result_buffer_done;

  logic result_sender_busy;
  logic result_sender_done;

  logic [31:0] windows_seen;
  logic [31:0] outputs_seen;
  logic [31:0] result_bytes_written;
  logic [31:0] result_bytes_read;
  logic [31:0] result_bytes_stored;
  logic [31:0] result_bytes_sent;

  // LED sticky/debug state
  logic led_done_q;
  logic led_error_q;

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

  uart_cmd_decoder #(
    .NUM_INPUT_CHANNELS(3),
    .NUM_OUTPUT_CHANNELS(4),
    .KERNEL_TAPS(9)
  ) u_cmd_decoder (
    .clk(clk),
    .rst_n(rst_n),
    .clear(1'b0),

    .rx_data(rx_data),
    .rx_valid(rx_valid),

    .ping_valid(ping_valid),
    .read_request_valid(read_request_valid),

    .cfg_valid(cfg_valid),
    .cfg_width(cfg_width),
    .cfg_height(cfg_height),
    .cfg_kernel_mode(cfg_kernel_mode),
    .cfg_relu_enable(cfg_relu_enable),
    .cfg_bias_enable(cfg_bias_enable),
    .cfg_quant_enable(cfg_quant_enable),
    .cfg_quant_shift(cfg_quant_shift),

    .weight_valid(weight_valid),
    .weight_index(weight_index),
    .weight_data(weight_data),
    .weights_done(weights_done),

    .bias_valid(bias_valid),
    .bias_index(bias_index),
    .bias_data(bias_data),
    .bias_done(bias_done),

    .pixel_valid(pixel_valid),
    .pixel_index(pixel_index),
    .pixel_data(pixel_data),
    .image_length(image_length),
    .image_done(image_done),

    .protocol_error(protocol_error)
  );

  cnn_system_core #(
    .DATA_WIDTH(8),
    .WEIGHT_WIDTH(8),
    .ACC_WIDTH(32),
    .OUT_WIDTH(8),
    .BIAS_WIDTH(32),
    .NUM_INPUT_CHANNELS(3),
    .NUM_OUTPUT_CHANNELS(4),
    .KERNEL_TAPS(9),
    .MAX_IMG_WIDTH(64),
    .RESULT_DEPTH(RESULT_DEPTH)
  ) u_system_core (
    .clk(clk),
    .rst_n(rst_n),
    .clear(1'b0),

    .cfg_valid(cfg_valid),
    .cfg_width(cfg_width),
    .cfg_height(cfg_height),
    .cfg_kernel_mode(cfg_kernel_mode),
    .cfg_relu_enable(cfg_relu_enable),
    .cfg_bias_enable(cfg_bias_enable),
    .cfg_quant_enable(cfg_quant_enable),
    .cfg_quant_shift(cfg_quant_shift),

    .weight_valid(weight_valid),
    .weight_index(weight_index),
    .weight_data(weight_data),
    .weights_done(weights_done),

    .bias_valid(bias_valid),
    .bias_index(bias_index),
    .bias_data(bias_data),
    .bias_done(bias_done),

    .pixel_data(pixel_data),
    .pixel_valid(pixel_valid),
    .pixel_ready(pixel_ready),

    .read_request_valid(read_request_valid),

    .tx_data(tx_data),
    .tx_valid(tx_valid),
    .tx_ready(tx_ready),

    .config_loaded(config_loaded),
    .weights_loaded(weights_loaded),
    .bias_loaded(bias_loaded),
    .system_ready(system_ready),

    .result_buffer_full(result_buffer_full),
    .result_buffer_empty(result_buffer_empty),
    .result_buffer_done(result_buffer_done),

    .result_sender_busy(result_sender_busy),
    .result_sender_done(result_sender_done),

    .windows_seen(windows_seen),
    .outputs_seen(outputs_seen),
    .result_bytes_written(result_bytes_written),
    .result_bytes_read(result_bytes_read),
    .result_bytes_stored(result_bytes_stored),
    .result_bytes_sent(result_bytes_sent)
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

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      led_done_q  <= 1'b0;
      led_error_q <= 1'b0;
    end else begin
      if (result_sender_done) begin
        led_done_q <= ~led_done_q;
      end

      if (rx_framing_error || protocol_error || result_buffer_full) begin
        led_error_q <= 1'b1;
      end
    end
  end

  assign led_busy  = tx_busy || result_sender_busy || !system_ready;
  assign led_done  = led_done_q;
  assign led_error = led_error_q;

endmodule
