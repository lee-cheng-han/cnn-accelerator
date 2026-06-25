`timescale 1ns/1ps

module tb_cnn_system_core_compile;

  logic clk;
  logic rst_n;
  logic clear;

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

  logic signed [7:0] pixel_data;
  logic pixel_valid;
  logic pixel_ready;

  logic read_request_valid;

  logic [7:0] tx_data;
  logic tx_valid;
  logic tx_ready;

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

  cnn_system_core #(
    .RESULT_DEPTH(256)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),

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

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    clear = 1'b0;

    cfg_valid = 1'b0;
    cfg_width = 16'd0;
    cfg_height = 16'd0;
    cfg_kernel_mode = 1'b0;
    cfg_relu_enable = 1'b0;
    cfg_bias_enable = 1'b0;
    cfg_quant_enable = 1'b0;
    cfg_quant_shift = 5'd0;

    weight_valid = 1'b0;
    weight_index = 8'd0;
    weight_data = 8'sd0;
    weights_done = 1'b0;

    bias_valid = 1'b0;
    bias_index = 2'd0;
    bias_data = 32'sd0;
    bias_done = 1'b0;

    pixel_data = 8'sd0;
    pixel_valid = 1'b0;

    read_request_valid = 1'b0;
    tx_ready = 1'b1;

    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (20) @(posedge clk);

    $display("[PASS] tb_cnn_system_core_compile");
    $finish;
  end

endmodule
