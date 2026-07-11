`timescale 1ns/1ps

module output_tensor_store_controller #(
  parameter int MAX_PIXELS = 4096,
  parameter int MAX_COUT   = 64,
  parameter int DATA_W     = 8,
  parameter int DIM_W      = 16,
  parameter int COUNT_W    = 8,
  parameter int ADDR_W     = 32
)(
  input  logic clk,
  input  logic rst_n,

  input  logic start,
  input  logic [DIM_W-1:0] width,
  input  logic [DIM_W-1:0] height,
  input  logic [COUNT_W-1:0] channels,

  input  logic signed [DATA_W-1:0] output_tensor [MAX_PIXELS*MAX_COUT],

  output logic stream_valid,
  input  logic stream_ready,
  output logic signed [DATA_W-1:0] stream_data,
  output logic stream_last,
  output logic [ADDR_W-1:0] stream_pixel,
  output logic [COUNT_W-1:0] stream_channel,

  output logic busy,
  output logic done,
  output logic error
);

  typedef enum logic [1:0] {
    S_IDLE,
    S_STORE,
    S_DONE
  } state_t;

  state_t state;

  logic [ADDR_W-1:0] pixel_count;
  logic [ADDR_W-1:0] pixel_index;
  logic [ADDR_W-1:0] last_pixel_index_q;
  logic [COUNT_W-1:0] channel_index;
  logic [COUNT_W-1:0] last_channel_index_q;
  logic [ADDR_W-1:0] tensor_index;
  logic config_error;
  logic zero_length;
  logic transfer;
  logic last_channel;
  logic last_pixel;

  assign pixel_count = ADDR_W'(width) * ADDR_W'(height);
  assign tensor_index = (pixel_index * ADDR_W'(MAX_COUT)) + ADDR_W'(channel_index);
  assign config_error = (channels > COUNT_W'(MAX_COUT)) ||
                        (pixel_count > ADDR_W'(MAX_PIXELS));
  assign zero_length = (pixel_count == '0) || (channels == '0);
  assign transfer = stream_valid && stream_ready;
  assign last_channel = channel_index == last_channel_index_q;
  assign last_pixel = pixel_index == last_pixel_index_q;

  assign stream_valid = (state == S_STORE);
  assign stream_data = (tensor_index < ADDR_W'(MAX_PIXELS*MAX_COUT)) ? output_tensor[tensor_index] : '0;
  assign stream_last = (state == S_STORE) && last_channel && last_pixel;
  assign stream_pixel = pixel_index;
  assign stream_channel = channel_index;
  assign busy = (state == S_STORE);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      pixel_index <= '0;
      last_pixel_index_q <= '0;
      channel_index <= '0;
      last_channel_index_q <= '0;
      done <= 1'b0;
      error <= 1'b0;
    end else begin
      done <= 1'b0;

      case (state)
        S_IDLE: begin
          if (start) begin
            pixel_index <= '0;
            channel_index <= '0;
            last_pixel_index_q <= zero_length ? '0 : (pixel_count - ADDR_W'(1));
            last_channel_index_q <= (channels == '0) ? '0 : (channels - COUNT_W'(1));
            error <= config_error;
            state <= (config_error || zero_length) ? S_DONE : S_STORE;
          end
        end

        S_STORE: begin
          if (transfer) begin
            if (last_channel && last_pixel) begin
              state <= S_DONE;
            end else if (last_channel) begin
              channel_index <= '0;
              pixel_index <= pixel_index + ADDR_W'(1);
            end else begin
              channel_index <= channel_index + COUNT_W'(1);
            end
          end
        end

        S_DONE: begin
          done <= 1'b1;
          state <= S_IDLE;
        end

        default: begin
          state <= S_IDLE;
        end
      endcase
    end
  end

endmodule
