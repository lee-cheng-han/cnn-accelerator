`timescale 1ns/1ps

module cnn_axi_system_top #(
  parameter int AXI_ADDR_WIDTH      = 12,
  parameter int AXI_DATA_WIDTH      = 32,
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
  input  logic                         s_axi_aclk,
  input  logic                         s_axi_aresetn,

  input  logic [AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
  input  logic                         s_axi_awvalid,
  output logic                         s_axi_awready,

  input  logic [AXI_DATA_WIDTH-1:0]     s_axi_wdata,
  input  logic [(AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
  input  logic                         s_axi_wvalid,
  output logic                         s_axi_wready,

  output logic [1:0]                   s_axi_bresp,
  output logic                         s_axi_bvalid,
  input  logic                         s_axi_bready,

  input  logic [AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
  input  logic                         s_axi_arvalid,
  output logic                         s_axi_arready,

  output logic [AXI_DATA_WIDTH-1:0]     s_axi_rdata,
  output logic [1:0]                   s_axi_rresp,
  output logic                         s_axi_rvalid,
  input  logic                         s_axi_rready
);

  localparam int NUM_WEIGHTS = NUM_OUTPUT_CHANNELS * NUM_INPUT_CHANNELS * KERNEL_TAPS;

  logic start_pulse;
  logic clear_pulse;

  logic [15:0] axi_image_width;
  logic [15:0] axi_image_height;
  logic        axi_kernel_mode;
  logic        axi_relu_enable;
  logic        axi_bias_enable;
  logic        axi_quant_enable;
  logic [4:0]  axi_quant_shift;

  logic        axi_weight_valid;
  logic [7:0]  axi_weight_index;
  logic signed [WEIGHT_WIDTH-1:0] axi_weight_data;

  logic        axi_bias_valid;
  logic [1:0]  axi_bias_index;
  logic signed [BIAS_WIDTH-1:0] axi_bias_data;

  logic        axi_pixel_valid;
  logic [31:0] axi_pixel_index;
  logic signed [DATA_WIDTH-1:0] axi_pixel_data;

  logic [15:0] cfg_image_width;
  logic [15:0] cfg_image_height;
  logic        cfg_kernel_mode;
  logic        cfg_relu_enable;
  logic        cfg_bias_enable;
  logic        cfg_quant_enable;
  logic [4:0]  cfg_quant_shift;

  logic signed [WEIGHT_WIDTH-1:0] weights
    [NUM_OUTPUT_CHANNELS][NUM_INPUT_CHANNELS][KERNEL_TAPS];

  logic signed [BIAS_WIDTH-1:0] bias
    [NUM_OUTPUT_CHANNELS];

  logic config_loaded;
  logic weights_loaded;
  logic bias_loaded;

  logic [31:0] cfg_write_count;
  logic [31:0] weight_write_count;
  logic [31:0] bias_write_count;

  logic weights_done;
  logic bias_done;

  logic core_pixel_ready;
  logic        core_pixel_valid;
  logic signed [DATA_WIDTH-1:0] core_pixel_data;
  logic        pixel_pending;
  logic        pixel_consume;
  logic signed [DATA_WIDTH-1:0] pixel_pending_data;
  logic core_out_valid;
  logic signed [OUT_WIDTH-1:0] core_out_data;
  logic core_out_last;
  logic core_out_ready;

  logic [31:0] windows_seen;
  logic [31:0] outputs_seen;

  logic result_valid;
  logic signed [DATA_WIDTH-1:0] result_data;
  logic result_last;
  logic result_ready;

  logic result_full;
  logic result_empty;
  logic result_done;
  logic [$clog2(RESULT_DEPTH+1)-1:0] result_write_count;
  logic [$clog2(RESULT_DEPTH+1)-1:0] result_read_count;
  logic [$clog2(RESULT_DEPTH+1)-1:0] result_stored_count;

  logic running;

  assign weights_done =
    axi_weight_valid && (axi_weight_index == (NUM_WEIGHTS - 1));

  assign bias_done =
    axi_bias_valid && (axi_bias_index == (NUM_OUTPUT_CHANNELS - 1));

  always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
      running <= 1'b0;
    end else if (clear_pulse) begin
      running <= 1'b0;
    end else if (start_pulse) begin
      running <= 1'b1;
    end else if (result_done) begin
      running <= 1'b0;
    end
  end


  // AXI writes are single-cycle pulses, but the CNN stream input uses
  // valid/ready. Hold one pixel until the CNN accepts it.
  //
  // Important case:
  // If the CNN consumes the old pixel in the same cycle that AXI writes
  // a new pixel, replace the old value with the new value instead of
  // clearing the pending register. Otherwise every other pixel can be lost.
  assign pixel_consume = core_pixel_valid && core_pixel_ready;

  always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
      pixel_pending      <= 1'b0;
      pixel_pending_data <= '0;
    end else if (clear_pulse) begin
      pixel_pending      <= 1'b0;
      pixel_pending_data <= '0;
    end else begin
      unique case ({axi_pixel_valid, pixel_consume})
        2'b00: begin
          pixel_pending <= pixel_pending;
        end

        2'b01: begin
          pixel_pending <= 1'b0;
        end

        2'b10: begin
          pixel_pending      <= 1'b1;
          pixel_pending_data <= axi_pixel_data;
        end

        2'b11: begin
          pixel_pending      <= 1'b1;
          pixel_pending_data <= axi_pixel_data;
        end
      endcase
    end
  end

  assign core_pixel_valid = pixel_pending && config_loaded;
  assign core_pixel_data  = pixel_pending_data;

  cnn_axi_lite_slave #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .NUM_INPUT_CHANNELS(NUM_INPUT_CHANNELS),
    .NUM_OUTPUT_CHANNELS(NUM_OUTPUT_CHANNELS),
    .KERNEL_TAPS(KERNEL_TAPS),
    .DATA_WIDTH(DATA_WIDTH),
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .BIAS_WIDTH(BIAS_WIDTH)
  ) u_axi_slave (
    .s_axi_aclk(s_axi_aclk),
    .s_axi_aresetn(s_axi_aresetn),

    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),

    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),

    .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),

    .s_axi_araddr(s_axi_araddr),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),

    .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready),

    .start_pulse(start_pulse),
    .clear_pulse(clear_pulse),

    .image_width(axi_image_width),
    .image_height(axi_image_height),
    .kernel_mode(axi_kernel_mode),
    .relu_enable(axi_relu_enable),
    .bias_enable(axi_bias_enable),
    .quant_enable(axi_quant_enable),
    .quant_shift(axi_quant_shift),

    .weight_valid(axi_weight_valid),
    .weight_index(axi_weight_index),
    .weight_data(axi_weight_data),

    .bias_valid(axi_bias_valid),
    .bias_index(axi_bias_index),
    .bias_data(axi_bias_data),

    .pixel_valid(axi_pixel_valid),
    .pixel_index(axi_pixel_index),
    .pixel_data(axi_pixel_data),

    .core_busy(running),
    .core_done(result_done),
    .result_valid(result_valid),
    .result_data(result_data),
    .result_last(result_last),
    .result_ready(result_ready)
  );

  cnn_config_loader #(
    .NUM_INPUT_CHANNELS(NUM_INPUT_CHANNELS),
    .NUM_OUTPUT_CHANNELS(NUM_OUTPUT_CHANNELS),
    .KERNEL_TAPS(KERNEL_TAPS),
    .DATA_WIDTH(DATA_WIDTH),
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .BIAS_WIDTH(BIAS_WIDTH)
  ) u_config_loader (
    .clk(s_axi_aclk),
    .rst_n(s_axi_aresetn),
    .clear(clear_pulse),

    .cfg_valid(start_pulse),
    .cfg_width(axi_image_width),
    .cfg_height(axi_image_height),
    .cfg_kernel_mode(axi_kernel_mode),
    .cfg_relu_enable(axi_relu_enable),
    .cfg_bias_enable(axi_bias_enable),
    .cfg_quant_enable(axi_quant_enable),
    .cfg_quant_shift(axi_quant_shift),

    .weight_valid(axi_weight_valid),
    .weight_index(axi_weight_index),
    .weight_data(axi_weight_data),
    .weights_done(weights_done),

    .bias_valid(axi_bias_valid),
    .bias_index(axi_bias_index),
    .bias_data(axi_bias_data),
    .bias_done(bias_done),

    .image_width(cfg_image_width),
    .image_height(cfg_image_height),
    .kernel_mode(cfg_kernel_mode),
    .relu_enable(cfg_relu_enable),
    .bias_enable(cfg_bias_enable),
    .quant_enable(cfg_quant_enable),
    .quant_shift(cfg_quant_shift),

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
    .clk(s_axi_aclk),
    .rst_n(s_axi_aresetn),
    .clear(clear_pulse),

    .image_width(cfg_image_width),
    .image_height(cfg_image_height),
    .kernel_mode(cfg_kernel_mode),

    .s_pixel_data(core_pixel_data),
    .s_pixel_valid(core_pixel_valid),
    .s_pixel_ready(core_pixel_ready),

    .weights(weights),
    .bias(bias),

    .relu_enable(cfg_relu_enable),
    .bias_enable(cfg_bias_enable),
    .quant_enable(cfg_quant_enable),
    .quant_shift(cfg_quant_shift),

    .m_axis_tdata(core_out_data),
    .m_axis_tvalid(core_out_valid),
    .m_axis_tready(core_out_ready),
    .m_axis_tlast(core_out_last),

    .windows_seen(windows_seen),
    .outputs_seen(outputs_seen)
  );

  output_result_buffer #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH(RESULT_DEPTH)
  ) u_result_buffer (
    .clk(s_axi_aclk),
    .rst_n(s_axi_aresetn),
    .clear(clear_pulse),

    .wr_data(core_out_data),
    .wr_valid(core_out_valid),
    .wr_last(core_out_last),
    .wr_ready(core_out_ready),

    .rd_data(result_data),
    .rd_valid(result_valid),
    .rd_last(result_last),
    .rd_ready(result_ready),

    .full(result_full),
    .empty(result_empty),
    .done(result_done),

    .write_count(result_write_count),
    .read_count(result_read_count),
    .stored_count(result_stored_count)
  );

endmodule
