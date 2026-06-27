`timescale 1ns/1ps

module streaming_window_buffer #(
  parameter int DATA_WIDTH         = 8,
  parameter int NUM_INPUT_CHANNELS = 3,
  parameter int MAX_IMG_WIDTH      = 64
)(
  input  logic clk,
  input  logic rst_n,
  input  logic clear,

  input  logic [15:0] image_width,
  input  logic [15:0] image_height,

  input  logic signed [DATA_WIDTH-1:0] pixel_data,
  input  logic pixel_valid,
  output logic pixel_ready,

  output logic window_valid,
  output logic [15:0] window_x,
  output logic [15:0] window_y,
  output logic signed [DATA_WIDTH-1:0] window_data [NUM_INPUT_CHANNELS][9]
);

  localparam int CH_W = (NUM_INPUT_CHANNELS <= 1) ? 1 : $clog2(NUM_INPUT_CHANNELS);
  localparam int X_W  = (MAX_IMG_WIDTH <= 1) ? 1 : $clog2(MAX_IMG_WIDTH);

  logic [CH_W-1:0] cur_ch;
  logic [15:0] cur_x;
  logic [15:0] cur_y;

  // Two previous rows per channel. These are intentionally not reset so they
  // can infer FPGA memory more easily.
    logic signed [DATA_WIDTH-1:0] row_m2 [NUM_INPUT_CHANNELS][MAX_IMG_WIDTH];

    logic signed [DATA_WIDTH-1:0] row_m1 [NUM_INPUT_CHANNELS][MAX_IMG_WIDTH];

  // Horizontal shift registers for the three rows.
  logic signed [DATA_WIDTH-1:0] top_s0 [NUM_INPUT_CHANNELS];
  logic signed [DATA_WIDTH-1:0] top_s1 [NUM_INPUT_CHANNELS];
  logic signed [DATA_WIDTH-1:0] top_s2 [NUM_INPUT_CHANNELS];

  logic signed [DATA_WIDTH-1:0] mid_s0 [NUM_INPUT_CHANNELS];
  logic signed [DATA_WIDTH-1:0] mid_s1 [NUM_INPUT_CHANNELS];
  logic signed [DATA_WIDTH-1:0] mid_s2 [NUM_INPUT_CHANNELS];

  logic signed [DATA_WIDTH-1:0] bot_s0 [NUM_INPUT_CHANNELS];
  logic signed [DATA_WIDTH-1:0] bot_s1 [NUM_INPUT_CHANNELS];
  logic signed [DATA_WIDTH-1:0] bot_s2 [NUM_INPUT_CHANNELS];

  logic signed [DATA_WIDTH-1:0] top_new0;
  logic signed [DATA_WIDTH-1:0] top_new1;
  logic signed [DATA_WIDTH-1:0] top_new2;

  logic signed [DATA_WIDTH-1:0] mid_new0;
  logic signed [DATA_WIDTH-1:0] mid_new1;
  logic signed [DATA_WIDTH-1:0] mid_new2;

  logic signed [DATA_WIDTH-1:0] bot_new0;
  logic signed [DATA_WIDTH-1:0] bot_new1;
  logic signed [DATA_WIDTH-1:0] bot_new2;

  logic signed [DATA_WIDTH-1:0] row_m2_read;
  logic signed [DATA_WIDTH-1:0] row_m1_read;

  assign pixel_ready = 1'b1;

  always_comb begin
    row_m2_read = row_m2[cur_ch][X_W'(cur_x)];
    row_m1_read = row_m1[cur_ch][X_W'(cur_x)];

    top_new0 = top_s1[cur_ch];
    top_new1 = top_s2[cur_ch];
    top_new2 = row_m2_read;

    mid_new0 = mid_s1[cur_ch];
    mid_new1 = mid_s2[cur_ch];
    mid_new2 = row_m1_read;

    bot_new0 = bot_s1[cur_ch];
    bot_new1 = bot_s2[cur_ch];
    bot_new2 = pixel_data;
  end

  // Row memories are intentionally not reset.
  // Keep them in a clock-only process so Vivado does not infer reset/set
  // behavior on every memory element.
  always_ff @(posedge clk) begin
    if (rst_n && !clear && pixel_valid) begin
      row_m2[cur_ch][X_W'(cur_x)] <= row_m1_read;
      row_m1[cur_ch][X_W'(cur_x)] <= pixel_data;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cur_ch       <= '0;
      cur_x        <= 16'd0;
      cur_y        <= 16'd0;
      window_valid <= 1'b0;
      window_x     <= 16'd0;
      window_y     <= 16'd0;

      for (int c = 0; c < NUM_INPUT_CHANNELS; c++) begin
        top_s0[c] <= '0;
        top_s1[c] <= '0;
        top_s2[c] <= '0;

        mid_s0[c] <= '0;
        mid_s1[c] <= '0;
        mid_s2[c] <= '0;

        bot_s0[c] <= '0;
        bot_s1[c] <= '0;
        bot_s2[c] <= '0;

        for (int k = 0; k < 9; k++) begin
          window_data[c][k] <= '0;
        end
      end
    end else begin
      window_valid <= 1'b0;

      if (clear) begin
        cur_ch       <= '0;
        cur_x        <= 16'd0;
        cur_y        <= 16'd0;
        window_valid <= 1'b0;
        window_x     <= 16'd0;
        window_y     <= 16'd0;

        for (int c = 0; c < NUM_INPUT_CHANNELS; c++) begin
          top_s0[c] <= '0;
          top_s1[c] <= '0;
          top_s2[c] <= '0;

          mid_s0[c] <= '0;
          mid_s1[c] <= '0;
          mid_s2[c] <= '0;

          bot_s0[c] <= '0;
          bot_s1[c] <= '0;
          bot_s2[c] <= '0;
        end
      end else if (pixel_valid) begin
        // Update horizontal shifts for this channel.
        top_s0[cur_ch] <= top_new0;
        top_s1[cur_ch] <= top_new1;
        top_s2[cur_ch] <= top_new2;

        mid_s0[cur_ch] <= mid_new0;
        mid_s1[cur_ch] <= mid_new1;
        mid_s2[cur_ch] <= mid_new2;

        bot_s0[cur_ch] <= bot_new0;
        bot_s1[cur_ch] <= bot_new1;
        bot_s2[cur_ch] <= bot_new2;

        // A full multi-channel 3x3 window is ready after the last channel
        // of a spatial pixel has arrived, once x >= 2 and y >= 2.
        if ((cur_ch == NUM_INPUT_CHANNELS - 1) && (cur_x >= 16'd2) && (cur_y >= 16'd2)) begin
          window_valid <= 1'b1;
          window_x     <= cur_x - 16'd2;
          window_y     <= cur_y - 16'd2;

          for (int c = 0; c < NUM_INPUT_CHANNELS; c++) begin
            if (c == cur_ch) begin
              window_data[c][0] <= top_new0;
              window_data[c][1] <= top_new1;
              window_data[c][2] <= top_new2;

              window_data[c][3] <= mid_new0;
              window_data[c][4] <= mid_new1;
              window_data[c][5] <= mid_new2;

              window_data[c][6] <= bot_new0;
              window_data[c][7] <= bot_new1;
              window_data[c][8] <= bot_new2;
            end else begin
              window_data[c][0] <= top_s0[c];
              window_data[c][1] <= top_s1[c];
              window_data[c][2] <= top_s2[c];

              window_data[c][3] <= mid_s0[c];
              window_data[c][4] <= mid_s1[c];
              window_data[c][5] <= mid_s2[c];

              window_data[c][6] <= bot_s0[c];
              window_data[c][7] <= bot_s1[c];
              window_data[c][8] <= bot_s2[c];
            end
          end
        end

        // Advance channel/x/y counters.
        if (cur_ch == NUM_INPUT_CHANNELS - 1) begin
          cur_ch <= '0;

          if (cur_x == image_width - 16'd1) begin
            cur_x <= 16'd0;

            if (cur_y == image_height - 16'd1) begin
              cur_y <= 16'd0;
            end else begin
              cur_y <= cur_y + 16'd1;
            end

            // Clear horizontal shift registers at row boundary.
            for (int c = 0; c < NUM_INPUT_CHANNELS; c++) begin
              top_s0[c] <= '0;
              top_s1[c] <= '0;
              top_s2[c] <= '0;

              mid_s0[c] <= '0;
              mid_s1[c] <= '0;
              mid_s2[c] <= '0;

              bot_s0[c] <= '0;
              bot_s1[c] <= '0;
              bot_s2[c] <= '0;
            end
          end else begin
            cur_x <= cur_x + 16'd1;
          end
        end else begin
          cur_ch <= cur_ch + 1'b1;
        end
      end
    end
  end

endmodule
