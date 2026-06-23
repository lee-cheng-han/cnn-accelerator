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
  output logic output_last_en,

  output logic [$clog2(MAX_PIXELS)-1:0]          load_addr,
  output logic [$clog2(MAX_PIXELS)-1:0]          out_pixel_addr,
  output logic [$clog2(NUM_INPUT_CHANNELS)-1:0]  load_ic,
  output logic [$clog2(NUM_OUTPUT_CHANNELS)-1:0] out_oc,

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

  localparam int ADDR_W = $clog2(MAX_PIXELS);

  logic [15:0] out_w_calc;
  logic [15:0] out_h_calc;

  logic [15:0] out_w_q;
  logic [15:0] out_h_q;

  logic [31:0] image_pixels_calc;
  logic [31:0] output_pixels_calc;

  logic [31:0] image_pixels_q;
  logic [31:0] output_pixels_q;

  logic [31:0] load_addr_32;
  logic [31:0] out_pixel_addr_32;
  logic [31:0] load_ic_32;
  logic [31:0] out_oc_32;

  logic input_last_transfer;
  logic output_last_transfer;

  assign out_w_calc = (image_width  >= 16'd3) ? (image_width  - 16'd2) : 16'd0;
  assign out_h_calc = (image_height >= 16'd3) ? (image_height - 16'd2) : 16'd0;

  assign image_pixels_calc  = {16'd0, image_width} * {16'd0, image_height};
  assign output_pixels_calc = {16'd0, out_w_calc} * {16'd0, out_h_calc};

  assign load_addr_32      = {{(32-$bits(load_addr)){1'b0}}, load_addr};
  assign out_pixel_addr_32 = {{(32-$bits(out_pixel_addr)){1'b0}}, out_pixel_addr};
  assign load_ic_32        = {{(32-$bits(load_ic)){1'b0}}, load_ic};
  assign out_oc_32         = {{(32-$bits(out_oc)){1'b0}}, out_oc};

  assign input_last_transfer =
    input_fire &&
    (image_pixels_q != 32'd0) &&
    (load_addr_32 == image_pixels_q - 32'd1) &&
    (load_ic_32 == NUM_INPUT_CHANNELS - 1);

  assign output_last_transfer =
    output_fire &&
    (output_pixels_q != 32'd0) &&
    (out_pixel_addr_32 == output_pixels_q - 32'd1) &&
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
        if (image_pixels_q == 32'd0) begin
          next_state = S_DONE;
        end else if (input_last_transfer) begin
          next_state = S_COMPUTE;
        end
      end

      S_COMPUTE: begin
        if (output_pixels_q == 32'd0) begin
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
      load_addr       <= '0;
      out_pixel_addr  <= '0;
      load_ic         <= '0;
      out_oc          <= '0;

      out_x           <= 16'd0;
      out_y           <= 16'd0;
      out_base_addr   <= '0;

      out_w_q         <= 16'd0;
      out_h_q         <= 16'd0;
      image_pixels_q  <= 32'd0;
      output_pixels_q <= 32'd0;

      done            <= 1'b0;
    end else begin
      done <= 1'b0;

      if ((state == S_IDLE) && start) begin
        load_addr       <= '0;
        out_pixel_addr  <= '0;
        load_ic         <= '0;
        out_oc          <= '0;

        out_x           <= 16'd0;
        out_y           <= 16'd0;
        out_base_addr   <= '0;

        out_w_q         <= out_w_calc;
        out_h_q         <= out_h_calc;
        image_pixels_q  <= image_pixels_calc;
        output_pixels_q <= output_pixels_calc;
      end

      if ((state == S_LOAD) && input_fire && (image_pixels_q != 32'd0)) begin
        if (load_addr_32 == image_pixels_q - 32'd1) begin
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

      if ((state == S_COMPUTE) && output_fire && (output_pixels_q != 32'd0)) begin
        if (out_oc_32 == NUM_OUTPUT_CHANNELS - 1) begin
          out_oc <= '0;

          if (out_pixel_addr_32 == output_pixels_q - 32'd1) begin
            out_pixel_addr <= '0;
            out_x          <= 16'd0;
            out_y          <= 16'd0;
            out_base_addr  <= '0;
          end else begin
            out_pixel_addr <= out_pixel_addr + 1'b1;

            if (out_x == out_w_q - 16'd1) begin
              out_x         <= 16'd0;
              out_y         <= out_y + 1'b1;
              out_base_addr <= out_base_addr + ADDR_W'(3);
            end else begin
              out_x         <= out_x + 1'b1;
              out_base_addr <= out_base_addr + ADDR_W'(1);
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
    output_valid_en = (state == S_COMPUTE) && (output_pixels_q != 32'd0);

    output_last_en =
      output_valid_en &&
      (out_pixel_addr_32 == output_pixels_q - 32'd1) &&
      (out_oc_32 == NUM_OUTPUT_CHANNELS - 1);
  end

endmodule
