`timescale 1ns/1ps

module cnn_accel_top #(
  parameter int DATA_WIDTH_P           = cnn_accel_pkg::DATA_WIDTH,
  parameter int WEIGHT_WIDTH_P         = cnn_accel_pkg::WEIGHT_WIDTH,
  parameter int ACC_WIDTH_P            = cnn_accel_pkg::ACC_WIDTH,
  parameter int OUT_WIDTH_P            = cnn_accel_pkg::OUT_WIDTH,
  parameter int BIAS_WIDTH_P           = cnn_accel_pkg::BIAS_WIDTH,
  parameter int NUM_INPUT_CHANNELS_P   = cnn_accel_pkg::NUM_INPUT_CHANNELS,
  parameter int NUM_OUTPUT_CHANNELS_P  = cnn_accel_pkg::NUM_OUTPUT_CHANNELS,
  parameter int KERNEL_TAPS_P          = cnn_accel_pkg::KERNEL_TAPS,
  parameter int MAX_IMG_WIDTH_P        = cnn_accel_pkg::MAX_IMG_WIDTH,
  parameter int MAX_IMG_HEIGHT_P       = cnn_accel_pkg::MAX_IMG_HEIGHT,
  parameter int MAX_PIXELS_P           = cnn_accel_pkg::MAX_PIXELS
)(
  input  logic clk,
  input  logic rst_n,

  input  logic cfg_we,
  input  logic [cnn_accel_pkg::CFG_ADDR_WIDTH-1:0] cfg_addr,
  input  logic [cnn_accel_pkg::CFG_DATA_WIDTH-1:0] cfg_wdata,
  output logic [cnn_accel_pkg::CFG_DATA_WIDTH-1:0] cfg_rdata,

  input  logic [DATA_WIDTH_P-1:0] s_axis_tdata,
  input  logic s_axis_tvalid,
  output logic s_axis_tready,
  input  logic s_axis_tlast,

  output logic [OUT_WIDTH_P-1:0] m_axis_tdata,
  output logic m_axis_tvalid,
  input  logic m_axis_tready,
  output logic m_axis_tlast,

  output logic busy,
  output logic done,

  output logic [31:0] cycle_count,
  output logic [31:0] input_pixel_count,
  output logic [31:0] window_count,
  output logic [31:0] mac_count,
  output logic [31:0] output_count,
  output logic [31:0] stall_count,
  output logic [31:0] fifo_full_count
);

  localparam int ADDR_W = $clog2(MAX_PIXELS_P);

  logic start_pulse;

  logic [15:0] image_width;
  logic [15:0] image_height;

  logic relu_enable;
  logic bias_enable;
  logic quant_enable;
  logic kernel_mode;
  logic [4:0] quant_shift;

  logic relu_enable_q;
  logic bias_enable_q;
  logic quant_enable_q;
  logic kernel_mode_q;
  logic [4:0] quant_shift_q;

  logic signed [WEIGHT_WIDTH_P-1:0] cfg_weights
    [NUM_OUTPUT_CHANNELS_P][NUM_INPUT_CHANNELS_P][KERNEL_TAPS_P];

  logic signed [BIAS_WIDTH_P-1:0] cfg_bias
    [NUM_OUTPUT_CHANNELS_P];

  logic loading;

  /* verilator lint_off UNUSEDSIGNAL */
  logic computing;
  /* verilator lint_on UNUSEDSIGNAL */

  logic output_valid_en;
  logic output_last_en;

  logic [ADDR_W-1:0] load_addr;
  logic [ADDR_W-1:0] out_pixel_addr;
  logic [ADDR_W-1:0] out_base_addr;

  logic [$clog2(NUM_INPUT_CHANNELS_P)-1:0] load_ic;
  logic [$clog2(NUM_OUTPUT_CHANNELS_P)-1:0] out_oc;

  logic [15:0] out_x;
  logic [15:0] out_y;

  logic input_fire;
  logic output_ready;
  logic output_fire;

  logic signed [DATA_WIDTH_P-1:0] pixel_data;
  logic pixel_valid;

  /* verilator lint_off UNUSEDSIGNAL */
  logic pixel_last_unused;
  logic [15:0] out_x_unused;
  logic [15:0] out_y_unused;
  logic signed [ACC_WIDTH_P-1:0] compute_acc_unused;
  logic [ADDR_W-1:0] out_pixel_addr_unused;
  /* verilator lint_on UNUSEDSIGNAL */

  logic signed [DATA_WIDTH_P-1:0] windows
    [NUM_INPUT_CHANNELS_P][KERNEL_TAPS_P];

  logic signed [DATA_WIDTH_P-1:0] windows_q
    [NUM_INPUT_CHANNELS_P][KERNEL_TAPS_P];

  logic [$clog2(NUM_OUTPUT_CHANNELS_P)-1:0] out_oc_q;
  logic output_stage_valid;
  logic output_last_q;

  logic compute_valid_q;
  logic compute_last_q;

  logic conv_last_s1;
  logic conv_last_s2;
  logic conv_last_s3;
  logic conv_last_s4;

  logic [ADDR_W-1:0] rd_addr
    [NUM_INPUT_CHANNELS_P][KERNEL_TAPS_P];

  logic [ADDR_W-1:0] row0_base;
  logic [ADDR_W-1:0] row1_base;
  logic [ADDR_W-1:0] row2_base;
  logic [ADDR_W-1:0] image_width_addr;
  logic [ADDR_W-1:0] two_image_width_addr;

  logic signed [WEIGHT_WIDTH_P-1:0] weights
    [NUM_OUTPUT_CHANNELS_P][NUM_INPUT_CHANNELS_P][KERNEL_TAPS_P];

  logic signed [BIAS_WIDTH_P-1:0] bias
    [NUM_OUTPUT_CHANNELS_P];

  logic signed [WEIGHT_WIDTH_P-1:0] weights_q
    [NUM_OUTPUT_CHANNELS_P][NUM_INPUT_CHANNELS_P][KERNEL_TAPS_P];

  logic signed [BIAS_WIDTH_P-1:0] bias_q
    [NUM_OUTPUT_CHANNELS_P];

  logic signed [WEIGHT_WIDTH_P-1:0] selected_weights
    [NUM_INPUT_CHANNELS_P][KERNEL_TAPS_P];

  logic signed [BIAS_WIDTH_P-1:0] selected_bias;

  logic signed [OUT_WIDTH_P-1:0] compute_out_comb;

  logic [31:0] out_oc_32;
  logic [31:0] last_output_channel_32;

  assign out_x_unused          = out_x;
  assign out_y_unused          = out_y;
  assign out_pixel_addr_unused = out_pixel_addr;

  assign out_oc_32 = {{(32-$bits(out_oc)){1'b0}}, out_oc};

  assign last_output_channel_32 = NUM_OUTPUT_CHANNELS_P - 1;

  assign image_width_addr     = ADDR_W'(image_width);
  assign two_image_width_addr = ADDR_W'(image_width << 1);

  assign row0_base = out_base_addr;
  assign row1_base = out_base_addr + image_width_addr;
  assign row2_base = out_base_addr + two_image_width_addr;

  axis_input_if #(
    .DATA_WIDTH(DATA_WIDTH_P)
  ) u_axis_in (
    .clk(clk),
    .rst_n(rst_n),
    .enable(loading),

    .s_axis_tdata(s_axis_tdata),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tlast(s_axis_tlast),

    .pixel_data(pixel_data),
    .pixel_valid(pixel_valid),
    .pixel_ready(1'b1),
    .pixel_last(pixel_last_unused)
  );

  assign input_fire = pixel_valid;

  config_regs #(
    .CFG_ADDR_WIDTH(cnn_accel_pkg::CFG_ADDR_WIDTH),
    .CFG_DATA_WIDTH(cnn_accel_pkg::CFG_DATA_WIDTH),
    .NUM_INPUT_CHANNELS(NUM_INPUT_CHANNELS_P),
    .NUM_OUTPUT_CHANNELS(NUM_OUTPUT_CHANNELS_P),
    .KERNEL_TAPS(KERNEL_TAPS_P),
    .MAX_IMG_WIDTH(MAX_IMG_WIDTH_P),
    .MAX_IMG_HEIGHT(MAX_IMG_HEIGHT_P)
  ) u_cfg (
    .clk(clk),
    .rst_n(rst_n),

    .cfg_we(cfg_we),
    .cfg_addr(cfg_addr),
    .cfg_wdata(cfg_wdata),
    .cfg_rdata(cfg_rdata),

    .done_status(done),
    .busy_status(busy),

    .start_pulse(start_pulse),
    .image_width(image_width),
    .image_height(image_height),

    .relu_enable(relu_enable),
    .bias_enable(bias_enable),
    .quant_enable(quant_enable),
    .kernel_mode(kernel_mode),
    .quant_shift(quant_shift),

    .weights(cfg_weights),
    .bias(cfg_bias)
  );

  accel_controller #(
    .NUM_INPUT_CHANNELS(NUM_INPUT_CHANNELS_P),
    .NUM_OUTPUT_CHANNELS(NUM_OUTPUT_CHANNELS_P),
    .MAX_PIXELS(MAX_PIXELS_P)
  ) u_ctrl (
    .clk(clk),
    .rst_n(rst_n),

    .start(start_pulse),
    .image_width(image_width),
    .image_height(image_height),
    .kernel_mode(kernel_mode),

    .input_fire(input_fire),
    .output_fire(output_fire),

    .busy(busy),
    .done(done),

    .loading(loading),
    .computing(computing),
    .output_valid_en(output_valid_en),
    .output_last_en(output_last_en),

    .load_addr(load_addr),
    .out_pixel_addr(out_pixel_addr),
    .load_ic(load_ic),
    .out_oc(out_oc),

    .out_x(out_x),
    .out_y(out_y),
    .out_base_addr(out_base_addr)
  );

  activation_buffer #(
    .DATA_WIDTH(DATA_WIDTH_P),
    .NUM_INPUT_CHANNELS(NUM_INPUT_CHANNELS_P),
    .MAX_PIXELS(MAX_PIXELS_P)
  ) u_act_buf (
    .clk(clk),

    .wr_en(input_fire),
    .wr_channel(load_ic),
    .wr_addr(load_addr),
    .wr_data(pixel_data),

    .rd_addr(rd_addr),
    .rd_window(windows)
  );

  weight_buffer #(
    .WEIGHT_WIDTH(WEIGHT_WIDTH_P),
    .BIAS_WIDTH(BIAS_WIDTH_P),
    .NUM_INPUT_CHANNELS(NUM_INPUT_CHANNELS_P),
    .NUM_OUTPUT_CHANNELS(NUM_OUTPUT_CHANNELS_P),
    .KERNEL_TAPS(KERNEL_TAPS_P)
  ) u_weight_buf (
    .cfg_weights(cfg_weights),
    .cfg_bias(cfg_bias),
    .weights(weights),
    .bias(bias)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      relu_enable_q  <= 1'b0;
      bias_enable_q  <= 1'b0;
      quant_enable_q <= 1'b0;
      kernel_mode_q  <= 1'b1;
      quant_shift_q  <= 5'd0;

      for (int oc = 0; oc < NUM_OUTPUT_CHANNELS_P; oc++) begin
        bias_q[oc] <= '0;

        for (int ic = 0; ic < NUM_INPUT_CHANNELS_P; ic++) begin
          for (int k = 0; k < KERNEL_TAPS_P; k++) begin
            weights_q[oc][ic][k] <= '0;
          end
        end
      end
    end else if (start_pulse) begin
      relu_enable_q  <= relu_enable;
      bias_enable_q  <= bias_enable;
      quant_enable_q <= quant_enable;
      kernel_mode_q  <= kernel_mode;
      quant_shift_q  <= quant_shift;

      for (int oc = 0; oc < NUM_OUTPUT_CHANNELS_P; oc++) begin
        bias_q[oc] <= bias[oc];

        for (int ic = 0; ic < NUM_INPUT_CHANNELS_P; ic++) begin
          for (int k = 0; k < KERNEL_TAPS_P; k++) begin
            weights_q[oc][ic][k] <= weights[oc][ic][k];
          end
        end
      end
    end
  end

  always_comb begin
    for (int c = 0; c < NUM_INPUT_CHANNELS_P; c++) begin
      rd_addr[c][0] = row0_base;
      rd_addr[c][1] = row0_base + ADDR_W'(1);
      rd_addr[c][2] = row0_base + ADDR_W'(2);

      rd_addr[c][3] = row1_base;
      rd_addr[c][4] = row1_base + ADDR_W'(1);
      rd_addr[c][5] = row1_base + ADDR_W'(2);

      rd_addr[c][6] = row2_base;
      rd_addr[c][7] = row2_base + ADDR_W'(1);
      rd_addr[c][8] = row2_base + ADDR_W'(2);
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      output_stage_valid <= 1'b0;
      output_last_q      <= 1'b0;
      out_oc_q           <= '0;

      for (int c = 0; c < NUM_INPUT_CHANNELS_P; c++) begin
        for (int k = 0; k < KERNEL_TAPS_P; k++) begin
          windows_q[c][k] <= '0;
        end
      end
    end else begin
      if (start_pulse) begin
        output_stage_valid <= 1'b0;
        output_last_q      <= 1'b0;
        out_oc_q           <= '0;

        for (int c = 0; c < NUM_INPUT_CHANNELS_P; c++) begin
          for (int k = 0; k < KERNEL_TAPS_P; k++) begin
            windows_q[c][k] <= '0;
          end
        end
      end else if (output_ready) begin
        output_stage_valid <= output_valid_en;
        output_last_q      <= output_last_en;
        out_oc_q           <= out_oc;

        for (int c = 0; c < NUM_INPUT_CHANNELS_P; c++) begin
          for (int k = 0; k < KERNEL_TAPS_P; k++) begin
            windows_q[c][k] <= windows[c][k];
          end
        end
      end
    end
  end

  always_comb begin
    selected_bias = bias_q[out_oc_q];

    for (int ic = 0; ic < NUM_INPUT_CHANNELS_P; ic++) begin
      for (int k = 0; k < KERNEL_TAPS_P; k++) begin
        selected_weights[ic][k] = weights_q[out_oc_q][ic][k];
      end
    end
  end

  conv_engine #(
    .DATA_WIDTH(DATA_WIDTH_P),
    .WEIGHT_WIDTH(WEIGHT_WIDTH_P),
    .ACC_WIDTH(ACC_WIDTH_P),
    .OUT_WIDTH(OUT_WIDTH_P),
    .BIAS_WIDTH(BIAS_WIDTH_P),
    .NUM_INPUT_CHANNELS(NUM_INPUT_CHANNELS_P),
    .KERNEL_TAPS(KERNEL_TAPS_P)
  ) u_conv_engine_selected (
    .clk(clk),
    .rst_n(rst_n),
    .pipe_en(output_ready),
    .valid_in(output_stage_valid),
    .kernel_mode(kernel_mode_q),

    .windows(windows_q),
    .weights(selected_weights),
    .bias(selected_bias),

    .relu_enable(relu_enable_q),
    .bias_enable(bias_enable_q),
    .quant_enable(quant_enable_q),
    .quant_shift(quant_shift_q),

    .valid_out(compute_valid_q),
    .acc_raw(compute_acc_unused),
    .out_data(compute_out_comb)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      conv_last_s1   <= 1'b0;
      conv_last_s2   <= 1'b0;
      conv_last_s3   <= 1'b0;
      conv_last_s4   <= 1'b0;
      compute_last_q <= 1'b0;
    end else begin
      if (start_pulse) begin
        conv_last_s1   <= 1'b0;
        conv_last_s2   <= 1'b0;
        conv_last_s3   <= 1'b0;
        conv_last_s4   <= 1'b0;
        compute_last_q <= 1'b0;
      end else if (output_ready) begin
        conv_last_s1   <= output_stage_valid && output_last_q;
        conv_last_s2   <= conv_last_s1;
        conv_last_s3   <= conv_last_s2;
        conv_last_s4   <= conv_last_s3;

        compute_last_q <= conv_last_s3;
      end
    end
  end

  axis_output_if #(
    .DATA_WIDTH(OUT_WIDTH_P)
  ) u_axis_out (
    .clk(clk),
    .rst_n(rst_n),

    .data_in(compute_out_comb),
    .data_valid(compute_valid_q),
    .data_ready(output_ready),
    .data_last(compute_last_q),

    .m_axis_tdata(m_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tlast(m_axis_tlast)
  );

  assign output_fire = output_valid_en && output_ready;

  perf_counters u_perf (
    .clk(clk),
    .rst_n(rst_n),

    .clear(start_pulse),
    .busy(busy),

    .input_fire(input_fire),
    .window_fire(output_fire && (out_oc_32 == last_output_channel_32)),
    .output_fire(output_fire),

    .stall(output_valid_en && !output_ready),
    .fifo_full(1'b0),

    .macs_per_window(
      kernel_mode_q ?
        16'(NUM_INPUT_CHANNELS_P * NUM_OUTPUT_CHANNELS_P * KERNEL_TAPS_P) :
        16'(NUM_INPUT_CHANNELS_P * NUM_OUTPUT_CHANNELS_P)
    ),

    .cycle_count(cycle_count),
    .input_pixel_count(input_pixel_count),
    .window_count(window_count),
    .mac_count(mac_count),
    .output_count(output_count),
    .stall_count(stall_count),
    .fifo_full_count(fifo_full_count)
  );

endmodule
