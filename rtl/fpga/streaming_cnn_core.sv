`timescale 1ns/1ps

module streaming_cnn_core #(
  parameter int DATA_WIDTH          = 8,
  parameter int WEIGHT_WIDTH        = 8,
  parameter int ACC_WIDTH           = 32,
  parameter int OUT_WIDTH           = 8,
  parameter int BIAS_WIDTH          = 32,
  parameter int NUM_INPUT_CHANNELS  = 3,
  parameter int NUM_OUTPUT_CHANNELS = 4,
  parameter int KERNEL_TAPS         = 9,
  parameter int MAX_IMG_WIDTH       = 64
)(
  input  logic clk,
  input  logic rst_n,
  input  logic clear,

  input  logic [15:0] image_width,
  input  logic [15:0] image_height,

  // 0 = 1x1 convolution
  // 1 = 3x3 convolution
  input  logic kernel_mode,

  input  logic signed [DATA_WIDTH-1:0] s_pixel_data,
  input  logic                         s_pixel_valid,
  output logic                         s_pixel_ready,

  input  logic signed [WEIGHT_WIDTH-1:0] weights
    [NUM_OUTPUT_CHANNELS][NUM_INPUT_CHANNELS][KERNEL_TAPS],

  input  logic signed [BIAS_WIDTH-1:0] bias
    [NUM_OUTPUT_CHANNELS],

  input  logic relu_enable,
  input  logic bias_enable,
  input  logic quant_enable,
  input  logic [4:0] quant_shift,

  output logic signed [OUT_WIDTH-1:0] m_axis_tdata,
  output logic                        m_axis_tvalid,
  input  logic                        m_axis_tready,
  output logic                        m_axis_tlast,

  output logic [31:0] windows_seen,
  output logic [31:0] outputs_seen
);

  typedef enum logic [1:0] {
    S_INPUT,
    S_FEED
  } state_t;

  state_t state;

  localparam int OC_W = (NUM_OUTPUT_CHANNELS <= 1) ? 1 : $clog2(NUM_OUTPUT_CHANNELS);
  localparam int IC_W = (NUM_INPUT_CHANNELS  <= 1) ? 1 : $clog2(NUM_INPUT_CHANNELS);

  localparam int OUT_FIFO_DEPTH = 32;
  localparam int OUT_FIFO_AW    = $clog2(OUT_FIFO_DEPTH);

  logic buffer_pixel_valid;
  logic buffer_pixel_ready;

  logic window_valid;
  logic [15:0] window_x;
  logic [15:0] window_y;

  logic signed [DATA_WIDTH-1:0] window_data
    [NUM_INPUT_CHANNELS][KERNEL_TAPS];

  logic signed [DATA_WIDTH-1:0] window_q
    [NUM_INPUT_CHANNELS][KERNEL_TAPS];

  logic signed [DATA_WIDTH-1:0] one_by_one_pixel
    [NUM_INPUT_CHANNELS];

  logic [IC_W-1:0] one_by_one_ch;
  logic [15:0] one_by_one_x;
  logic [15:0] one_by_one_y;

  logic [OC_W-1:0] feed_oc;

  logic signed [WEIGHT_WIDTH-1:0] selected_weights
    [NUM_INPUT_CHANNELS][KERNEL_TAPS];

  logic signed [BIAS_WIDTH-1:0] selected_bias;

  logic conv_valid_in;
  logic conv_valid_out;
  logic signed [ACC_WIDTH-1:0] conv_acc_unused;
  logic signed [OUT_WIDTH-1:0] conv_out;

  logic [31:0] total_windows_calc;
  logic [31:0] total_windows;
  logic [31:0] total_windows_w_operand;
  logic [31:0] total_windows_h_operand;
  logic [31:0] window_index;

  logic feed_last;
  logic conv_last_s1;
  logic conv_last_s2;
  logic conv_last_s3;
  logic conv_last_s4;
  logic conv_last_out;

  logic signed [OUT_WIDTH-1:0] out_fifo_data [OUT_FIFO_DEPTH];
  logic                        out_fifo_last [OUT_FIFO_DEPTH];

  logic [OUT_FIFO_AW-1:0] out_fifo_wr_ptr;
  logic [OUT_FIFO_AW-1:0] out_fifo_rd_ptr;
  logic [OUT_FIFO_AW:0]   out_fifo_count;

  logic out_fifo_empty;
  logic out_fifo_full;
  logic out_fifo_almost_full;
  logic out_fifo_wr_en;
  logic out_fifo_rd_en;
  logic conv_pipe_en;

  // Compute total number of output windows/pixels.
  //
  // Pipeline stage 1:
  //   image_width/image_height/kernel_mode -> registered multiply operands
  //
  // Pipeline stage 2:
  //   registered operands -> DSP multiply -> registered total_windows
  //
  // This avoids the long path:
  // image_width -> subtract/mux -> DSP input -> total_windows/last logic.
  assign total_windows_calc = total_windows_w_operand * total_windows_h_operand;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      total_windows_w_operand <= 32'd0;
      total_windows_h_operand <= 32'd0;
      total_windows           <= 32'd0;
    end else if (clear) begin
      total_windows_w_operand <= 32'd0;
      total_windows_h_operand <= 32'd0;
      total_windows           <= 32'd0;
    end else begin
      if (kernel_mode) begin
        if ((image_width >= 16'd3) && (image_height >= 16'd3)) begin
          total_windows_w_operand <= {16'd0, image_width - 16'd2};
          total_windows_h_operand <= {16'd0, image_height - 16'd2};
        end else begin
          total_windows_w_operand <= 32'd0;
          total_windows_h_operand <= 32'd0;
        end
      end else begin
        total_windows_w_operand <= {16'd0, image_width};
        total_windows_h_operand <= {16'd0, image_height};
      end

      total_windows <= total_windows_calc;
    end
  end

  assign out_fifo_empty       = (out_fifo_count == 0);
  assign out_fifo_full        = (out_fifo_count == OUT_FIFO_DEPTH);
  assign out_fifo_almost_full = (out_fifo_count >= OUT_FIFO_DEPTH - 4);

  // Stall compute before the FIFO gets full.
  assign conv_pipe_en  = !out_fifo_almost_full;
  assign conv_valid_in = (state == S_FEED) && conv_pipe_en;

  // 3x3 mode uses the streaming window buffer.
  // 1x1 mode collects one full pixel across all input channels directly.
  assign s_pixel_ready =
    (state == S_INPUT) &&
    (
      kernel_mode ?
        (!window_valid && buffer_pixel_ready) :
        1'b1
    );

  assign buffer_pixel_valid = kernel_mode && s_pixel_valid && s_pixel_ready;

  streaming_window_buffer #(
    .DATA_WIDTH(DATA_WIDTH),
    .NUM_INPUT_CHANNELS(NUM_INPUT_CHANNELS),
    .MAX_IMG_WIDTH(MAX_IMG_WIDTH)
  ) u_window_buffer (
    .clk(clk),
    .rst_n(rst_n),
    .clear(clear),

    .image_width(image_width),
    .image_height(image_height),

    .pixel_data(s_pixel_data),
    .pixel_valid(buffer_pixel_valid),
    .pixel_ready(buffer_pixel_ready),

    .window_valid(window_valid),
    .window_x(window_x),
    .window_y(window_y),
    .window_data(window_data)
  );

  always_comb begin
    selected_bias = bias[feed_oc];

    for (int ic = 0; ic < NUM_INPUT_CHANNELS; ic++) begin
      for (int k = 0; k < KERNEL_TAPS; k++) begin
        selected_weights[ic][k] = weights[feed_oc][ic][k];
      end
    end
  end

  assign feed_last =
    (total_windows != 32'd0) &&
    (window_index == total_windows - 32'd1) &&
    (feed_oc == NUM_OUTPUT_CHANNELS - 1);

  conv_engine #(
    .DATA_WIDTH(DATA_WIDTH),
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .OUT_WIDTH(OUT_WIDTH),
    .BIAS_WIDTH(BIAS_WIDTH),
    .NUM_INPUT_CHANNELS(NUM_INPUT_CHANNELS),
    .KERNEL_TAPS(KERNEL_TAPS)
  ) u_conv_engine (
    .clk(clk),
    .rst_n(rst_n),
    .pipe_en(conv_pipe_en),
    .valid_in(conv_valid_in),
    .kernel_mode(kernel_mode),

    .windows(window_q),
    .weights(selected_weights),
    .bias(selected_bias),

    .relu_enable(relu_enable),
    .bias_enable(bias_enable),
    .quant_enable(quant_enable),
    .quant_shift(quant_shift),

    .valid_out(conv_valid_out),
    .acc_raw(conv_acc_unused),
    .out_data(conv_out)
  );

  assign conv_last_out = conv_valid_out && conv_last_s4;

  assign out_fifo_wr_en = conv_valid_out && !out_fifo_full;
  assign out_fifo_rd_en = m_axis_tvalid && m_axis_tready;

  assign m_axis_tdata  = out_fifo_data[out_fifo_rd_ptr];
  assign m_axis_tvalid = !out_fifo_empty;
  assign m_axis_tlast  = out_fifo_last[out_fifo_rd_ptr];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state        <= S_INPUT;
      feed_oc      <= '0;
      window_index <= 32'd0;
      windows_seen <= 32'd0;
      outputs_seen <= 32'd0;

      one_by_one_ch <= '0;
      one_by_one_x  <= 16'd0;
      one_by_one_y  <= 16'd0;

      conv_last_s1 <= 1'b0;
      conv_last_s2 <= 1'b0;
      conv_last_s3 <= 1'b0;
      conv_last_s4 <= 1'b0;

      out_fifo_wr_ptr <= '0;
      out_fifo_rd_ptr <= '0;
      out_fifo_count  <= '0;

      for (int ic = 0; ic < NUM_INPUT_CHANNELS; ic++) begin
        one_by_one_pixel[ic] <= '0;

        for (int k = 0; k < KERNEL_TAPS; k++) begin
          window_q[ic][k] <= '0;
        end
      end

      for (int i = 0; i < OUT_FIFO_DEPTH; i++) begin
        out_fifo_data[i] <= '0;
        out_fifo_last[i] <= 1'b0;
      end
    end else begin
      if (clear) begin
        state        <= S_INPUT;
        feed_oc      <= '0;
        window_index <= 32'd0;
        windows_seen <= 32'd0;
        outputs_seen <= 32'd0;

        one_by_one_ch <= '0;
        one_by_one_x  <= 16'd0;
        one_by_one_y  <= 16'd0;

        conv_last_s1 <= 1'b0;
        conv_last_s2 <= 1'b0;
        conv_last_s3 <= 1'b0;
        conv_last_s4 <= 1'b0;

        out_fifo_wr_ptr <= '0;
        out_fifo_rd_ptr <= '0;
        out_fifo_count  <= '0;

        for (int ic = 0; ic < NUM_INPUT_CHANNELS; ic++) begin
          one_by_one_pixel[ic] <= '0;

          for (int k = 0; k < KERNEL_TAPS; k++) begin
            window_q[ic][k] <= '0;
          end
        end

        for (int i = 0; i < OUT_FIFO_DEPTH; i++) begin
          out_fifo_data[i] <= '0;
          out_fifo_last[i] <= 1'b0;
        end
      end else begin
        // Keep TLAST aligned with the conv_engine pipeline.
        // If the conv pipeline stalls, the TLAST sideband stalls too.
        if (conv_pipe_en) begin
          conv_last_s1 <= conv_valid_in && feed_last;
          conv_last_s2 <= conv_last_s1;
          conv_last_s3 <= conv_last_s2;
          conv_last_s4 <= conv_last_s3;
        end

        // Output FIFO.
        if (out_fifo_wr_en) begin
          out_fifo_data[out_fifo_wr_ptr] <= conv_out;
          out_fifo_last[out_fifo_wr_ptr] <= conv_last_out;
          out_fifo_wr_ptr <= out_fifo_wr_ptr + 1'b1;
        end

        if (out_fifo_rd_en) begin
          out_fifo_rd_ptr <= out_fifo_rd_ptr + 1'b1;
        end

        unique case ({out_fifo_wr_en, out_fifo_rd_en})
          2'b10: out_fifo_count <= out_fifo_count + 1'b1;
          2'b01: out_fifo_count <= out_fifo_count - 1'b1;
          default: out_fifo_count <= out_fifo_count;
        endcase

        if (out_fifo_rd_en) begin
          outputs_seen <= outputs_seen + 32'd1;
        end

        unique case (state)
          S_INPUT: begin
            feed_oc <= '0;

            if (kernel_mode) begin
              // 3x3 path: use streaming window buffer output.
              if (window_valid) begin
                for (int ic = 0; ic < NUM_INPUT_CHANNELS; ic++) begin
                  for (int k = 0; k < KERNEL_TAPS; k++) begin
                    window_q[ic][k] <= window_data[ic][k];
                  end
                end

                windows_seen <= windows_seen + 32'd1;
                state <= S_FEED;
              end
            end else begin
              // 1x1 path: collect all input channels for the current pixel.
              if (s_pixel_valid && s_pixel_ready) begin
                one_by_one_pixel[one_by_one_ch] <= s_pixel_data;

                if (one_by_one_ch == NUM_INPUT_CHANNELS - 1) begin
                  for (int ic = 0; ic < NUM_INPUT_CHANNELS; ic++) begin
                    for (int k = 0; k < KERNEL_TAPS; k++) begin
                      window_q[ic][k] <= '0;
                    end
                  end

                  for (int ic = 0; ic < NUM_INPUT_CHANNELS; ic++) begin
                    if (ic == one_by_one_ch) begin
                      window_q[ic][0] <= s_pixel_data;
                    end else begin
                      window_q[ic][0] <= one_by_one_pixel[ic];
                    end
                  end

                  windows_seen <= windows_seen + 32'd1;
                  state <= S_FEED;

                  one_by_one_ch <= '0;

                  if (one_by_one_x == image_width - 16'd1) begin
                    one_by_one_x <= 16'd0;

                    if (one_by_one_y == image_height - 16'd1) begin
                      one_by_one_y <= 16'd0;
                    end else begin
                      one_by_one_y <= one_by_one_y + 16'd1;
                    end
                  end else begin
                    one_by_one_x <= one_by_one_x + 16'd1;
                  end
                end else begin
                  one_by_one_ch <= one_by_one_ch + 1'b1;
                end
              end
            end
          end

          S_FEED: begin
            if (conv_pipe_en) begin
              if (feed_oc == NUM_OUTPUT_CHANNELS - 1) begin
                feed_oc <= '0;
                state   <= S_INPUT;

                if (window_index != total_windows) begin
                  window_index <= window_index + 32'd1;
                end
              end else begin
                feed_oc <= feed_oc + 1'b1;
              end
            end
          end

          default: begin
            state <= S_INPUT;
          end
        endcase
      end
    end
  end

endmodule
