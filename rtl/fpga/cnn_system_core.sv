`timescale 1ns/1ps

module cnn_system_core #(
  parameter int DATA_WIDTH          = 8,
  parameter int WEIGHT_WIDTH        = 8,
  parameter int ACC_WIDTH           = 32,
  parameter int OUT_WIDTH           = 8,
  parameter int BIAS_WIDTH          = 32,
  parameter int NUM_INPUT_CHANNELS  = 3,
  parameter int NUM_OUTPUT_CHANNELS = 4,
  parameter int KERNEL_TAPS         = 9,
  parameter int MAX_IMG_WIDTH       = 64,
  parameter int RESULT_DEPTH        = 16384
)(
  input  logic clk,
  input  logic rst_n,
  input  logic clear,

  // Decoded config command
  input  logic        cfg_valid,
  input  logic [15:0] cfg_width,
  input  logic [15:0] cfg_height,
  input  logic        cfg_kernel_mode,
  input  logic        cfg_relu_enable,
  input  logic        cfg_bias_enable,
  input  logic        cfg_quant_enable,
  input  logic [4:0]  cfg_quant_shift,

  // Decoded weight command
  input  logic        weight_valid,
  input  logic [7:0]  weight_index,
  input  logic signed [WEIGHT_WIDTH-1:0] weight_data,
  input  logic        weights_done,

  // Decoded bias command
  input  logic        bias_valid,
  input  logic [1:0]  bias_index,
  input  logic signed [BIAS_WIDTH-1:0] bias_data,
  input  logic        bias_done,

  // Decoded image stream
  input  logic signed [DATA_WIDTH-1:0] pixel_data,
  input  logic                         pixel_valid,
  output logic                         pixel_ready,

  // Decoded readback command
  input  logic read_request_valid,

  // Byte stream toward UART TX
  output logic [7:0] tx_data,
  output logic       tx_valid,
  input  logic       tx_ready,

  // Status/debug
  output logic config_loaded,
  output logic weights_loaded,
  output logic bias_loaded,
  output logic system_ready,

  output logic result_buffer_full,
  output logic result_buffer_empty,
  output logic result_buffer_done,

  output logic result_sender_busy,
  output logic result_sender_done,

  output logic [31:0] windows_seen,
  output logic [31:0] outputs_seen,
  output logic [31:0] result_bytes_written,
  output logic [31:0] result_bytes_read,
  output logic [31:0] result_bytes_stored,
  output logic [31:0] result_bytes_sent
);

  logic [15:0] image_width;
  logic [15:0] image_height;
  logic        kernel_mode;
  logic        relu_enable;
  logic        bias_enable;
  logic        quant_enable;
  logic [4:0]  quant_shift;

  logic signed [WEIGHT_WIDTH-1:0] weights
    [NUM_OUTPUT_CHANNELS][NUM_INPUT_CHANNELS][KERNEL_TAPS];

  logic signed [BIAS_WIDTH-1:0] bias
    [NUM_OUTPUT_CHANNELS];

  logic [31:0] cfg_write_count;
  logic [31:0] weight_write_count;
  logic [31:0] bias_write_count;

  logic signed [OUT_WIDTH-1:0] core_out_data;
  logic                        core_out_valid;
  logic                        core_out_ready;
  logic                        core_out_last;

  logic signed [OUT_WIDTH-1:0] buf_rd_data;
  logic                        buf_rd_valid;
  logic                        buf_rd_last;
  logic                        buf_rd_ready;

  logic [$clog2(RESULT_DEPTH+1)-1:0] buffer_write_count;
  logic [$clog2(RESULT_DEPTH+1)-1:0] buffer_read_count;
  logic [$clog2(RESULT_DEPTH+1)-1:0] buffer_stored_count;

  logic core_pixel_valid;
  logic core_pixel_ready;

  assign system_ready = config_loaded &&
                        weights_loaded &&
                        (!bias_enable || bias_loaded);

  assign core_pixel_valid = pixel_valid && system_ready;
  assign pixel_ready      = system_ready && core_pixel_ready;

  assign result_bytes_written = {{(32-$bits(buffer_write_count)){1'b0}}, buffer_write_count};
  assign result_bytes_read    = {{(32-$bits(buffer_read_count)){1'b0}}, buffer_read_count};
  assign result_bytes_stored  = {{(32-$bits(buffer_stored_count)){1'b0}}, buffer_stored_count};

  cnn_config_loader #(
    .NUM_INPUT_CHANNELS(NUM_INPUT_CHANNELS),
    .NUM_OUTPUT_CHANNELS(NUM_OUTPUT_CHANNELS),
    .KERNEL_TAPS(KERNEL_TAPS),
    .DATA_WIDTH(DATA_WIDTH),
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .BIAS_WIDTH(BIAS_WIDTH)
  ) u_config_loader (
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

    .image_width(image_width),
    .image_height(image_height),
    .kernel_mode(kernel_mode),
    .relu_enable(relu_enable),
    .bias_enable(bias_enable),
    .quant_enable(quant_enable),
    .quant_shift(quant_shift),

    .weights(weights),
    .bias(bias),

    .config_loaded(config_loaded),
    .weights_loaded(weights_loaded),
    .bias_loaded(bias_loaded),

    .cfg_write_count(cfg_write_count),
    .weight_write_count(weight_write_count),
    .bias_write_count(bias_write_count)
  );

  streaming_cnn_core #(
    .DATA_WIDTH(DATA_WIDTH),
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .OUT_WIDTH(OUT_WIDTH),
    .BIAS_WIDTH(BIAS_WIDTH),
    .NUM_INPUT_CHANNELS(NUM_INPUT_CHANNELS),
    .NUM_OUTPUT_CHANNELS(NUM_OUTPUT_CHANNELS),
    .KERNEL_TAPS(KERNEL_TAPS),
    .MAX_IMG_WIDTH(MAX_IMG_WIDTH)
  ) u_streaming_core (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),

    .image_width(image_width),
    .image_height(image_height),
    .kernel_mode(kernel_mode),

    .s_pixel_data(pixel_data),
    .s_pixel_valid(core_pixel_valid),
    .s_pixel_ready(core_pixel_ready),

    .weights(weights),
    .bias(bias),

    .relu_enable(relu_enable),
    .bias_enable(bias_enable),
    .quant_enable(quant_enable),
    .quant_shift(quant_shift),

    .m_axis_tdata(core_out_data),
    .m_axis_tvalid(core_out_valid),
    .m_axis_tready(core_out_ready),
    .m_axis_tlast(core_out_last),

    .windows_seen(windows_seen),
    .outputs_seen(outputs_seen)
  );

  output_result_buffer #(
    .DATA_WIDTH(OUT_WIDTH),
    .DEPTH(RESULT_DEPTH)
  ) u_result_buffer (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),

    .wr_data(core_out_data),
    .wr_valid(core_out_valid),
    .wr_last(core_out_last),
    .wr_ready(core_out_ready),

    .rd_data(buf_rd_data),
    .rd_valid(buf_rd_valid),
    .rd_last(buf_rd_last),
    .rd_ready(buf_rd_ready),

    .full(result_buffer_full),
    .empty(result_buffer_empty),
    .done(result_buffer_done),

    .write_count(buffer_write_count),
    .read_count(buffer_read_count),
    .stored_count(buffer_stored_count)
  );

  uart_result_sender #(
    .DATA_WIDTH(OUT_WIDTH)
  ) u_result_sender (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),

    .start(read_request_valid),

    .buf_rd_data(buf_rd_data),
    .buf_rd_valid(buf_rd_valid),
    .buf_rd_last(buf_rd_last),
    .buf_rd_ready(buf_rd_ready),

    .tx_data(tx_data),
    .tx_valid(tx_valid),
    .tx_ready(tx_ready),

    .busy(result_sender_busy),
    .done(result_sender_done),
    .bytes_sent(result_bytes_sent)
  );

endmodule
