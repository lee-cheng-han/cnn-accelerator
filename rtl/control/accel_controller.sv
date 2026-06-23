`timescale 1ns/1ps

module accel_controller #(
  parameter int NUM_INPUT_CHANNELS  = 3,
  parameter int NUM_OUTPUT_CHANNELS = 4,
  parameter int MAX_PIXELS          = 1024
)(
  input  logic clk,
  input  logic rst_n,

  input  logic start,
  input  logic [15:0] image_width,
  input  logic [15:0] image_height,

  input  logic input_fire,
  input  logic output_fire,

  output logic busy,
  output logic done,
  output logic loading,
  output logic computing,

  output logic output_valid_en,

  output logic [$clog2(MAX_PIXELS)-1:0]          load_addr,
  output logic [$clog2(MAX_PIXELS)-1:0]          out_pixel_addr,
  output logic [$clog2(NUM_INPUT_CHANNELS)-1:0]  load_ic,
  output logic [$clog2(NUM_OUTPUT_CHANNELS)-1:0] out_oc,

  // Counter-based output coordinates for timing-friendly address generation.
  output logic [15:0] out_x,
  output logic [15:0] out_y,
  output logic [$clog2(MAX_PIXELS)-1:0] out_base_addr
);

  typedef enum logic [1:0] {
    S_IDLE,
    S_LOAD,
    S_COMPUTE,
    S_DONE
  } state_t;

  state_t state;
  state_t next_state;

  logic [15:0] out_w;
  logic [15:0] out_h;

  logic [31:0] image_pixels;
  logic [31:0] output_pixels;

  logic [31:0] load_addr_32;
  logic [31:0] out_pixel_addr_32;
  logic [31:0] load_ic_32;
  logic [31:0] out_oc_32;

  logic input_last_transfer;
  logic output_last_transfer;

  assign out_w = (image_width  >= 16'd3) ? (image_width  - 16'd2) : 16'd0;
  assign out_h = (image_height >= 16'd3) ? (image_height - 16'd2) : 16'd0;

  assign image_pixels  = {16'd0, image_width} * {16'd0, image_height};
  assign output_pixels = {16'd0, out_w} * {16'd0, out_h};

  assign load_addr_32      = {{(32-$bits(load_addr)){1'b0}}, load_addr};
  assign out_pixel_addr_32 = {{(32-$bits(out_pixel_addr)){1'b0}}, out_pixel_addr};
  assign load_ic_32        = {{(32-$bits(load_ic)){1'b0}}, load_ic};
  assign out_oc_32         = {{(32-$bits(out_oc)){1'b0}}, out_oc};

  assign input_last_transfer =
    input_fire &&
    (image_pixels != 32'd0) &&
    (load_addr_32 == image_pixels - 32'd1) &&
    (load_ic_32 == NUM_INPUT_CHANNELS - 1);

  assign output_last_transfer =
    output_fire &&
    (output_pixels != 32'd0) &&
    (out_pixel_addr_32 == output_pixels - 32'd1) &&
    (out_oc_32 == NUM_OUTPUT_CHANNELS - 1);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
    end else begin
      state <= next_state;
    end
  end

  always_comb begin
    next_state = state;

    unique case (state)
      S_IDLE: begin
        if (start) begin
          next_state = S_LOAD;
        end
      end

      S_LOAD: begin
        if (image_pixels == 32'd0) begin
          next_state = S_DONE;
        end else if (input_last_transfer) begin
          next_state = S_COMPUTE;
        end
      end

      S_COMPUTE: begin
        if (output_pixels == 32'd0) begin
          next_state = S_DONE;
        end else if (output_last_transfer) begin
          next_state = S_DONE;
        end
      end

      S_DONE: begin
        next_state = S_IDLE;
      end

      default: begin
        next_state = S_IDLE;
      end
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      load_addr      <= '0;
      out_pixel_addr <= '0;
      load_ic        <= '0;
      out_oc         <= '0;

      out_x          <= 16'd0;
      out_y          <= 16'd0;
      out_base_addr  <= '0;

      done           <= 1'b0;
    end else begin
      done <= 1'b0;

      if ((state == S_IDLE) && start) begin
        load_addr      <= '0;
        out_pixel_addr <= '0;
        load_ic        <= '0;
        out_oc         <= '0;

        out_x          <= 16'd0;
        out_y          <= 16'd0;
        out_base_addr  <= '0;
      end

      // Load input image data channel-by-channel.
      if ((state == S_LOAD) && input_fire && (image_pixels != 32'd0)) begin
        if (load_addr_32 == image_pixels - 32'd1) begin
          load_addr <= '0;

          if (load_ic_32 == NUM_INPUT_CHANNELS - 1) begin
            load_ic <= '0;
          end else begin
            load_ic <= load_ic + 1'b1;
          end
        end else begin
          load_addr <= load_addr + 1'b1;
        end
      end

      // Output order:
      // pixel0_oc0, pixel0_oc1, pixel0_oc2, pixel0_oc3,
      // pixel1_oc0, ...
      if ((state == S_COMPUTE) && output_fire && (output_pixels != 32'd0)) begin
        if (out_oc_32 == NUM_OUTPUT_CHANNELS - 1) begin
          out_oc <= '0;

          if (out_pixel_addr_32 == output_pixels - 32'd1) begin
            out_pixel_addr <= '0;
            out_x          <= 16'd0;
            out_y          <= 16'd0;
            out_base_addr  <= '0;
          end else begin
            out_pixel_addr <= out_pixel_addr + 1'b1;

            if (out_x == out_w - 16'd1) begin
              out_x <= 16'd0;
              out_y <= out_y + 16'd1;

              // Last valid base address in row is row_start + (image_width - 3).
              // Next row start is row_start + image_width.
              // Difference is +3.
              out_base_addr <= out_base_addr + $clog2(MAX_PIXELS)'(3);
            end else begin
              out_x <= out_x + 16'd1;
              out_base_addr <= out_base_addr + 1'b1;
            end
          end
        end else begin
          out_oc <= out_oc + 1'b1;
        end
      end

      if (state == S_DONE) begin
        done <= 1'b1;
      end
    end
  end

  always_comb begin
    busy            = (state != S_IDLE);
    loading         = (state == S_LOAD);
    computing       = (state == S_COMPUTE);
    output_valid_en = (state == S_COMPUTE) && (output_pixels != 32'd0);
  end

endmodule
