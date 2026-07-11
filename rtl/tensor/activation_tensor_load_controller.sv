`timescale 1ns/1ps

module activation_tensor_load_controller #(
  parameter int MAX_PIXELS = 4096,
  parameter int MAX_C      = 64,
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

  input  logic stream_valid,
  output logic stream_ready,
  input  logic signed [DATA_W-1:0] stream_data,

  output logic write_enable,
  output logic [ADDR_W-1:0] write_pixel,
  output logic [COUNT_W-1:0] write_channel,
  output logic signed [DATA_W-1:0] write_data,

  output logic busy,
  output logic done,
  output logic error
);

  typedef enum logic [1:0] {
    S_IDLE,
    S_LOAD,
    S_DONE
  } state_t;

  state_t state;

  logic [ADDR_W-1:0] pixel_count;
  logic [ADDR_W-1:0] pixel_index;
  logic [ADDR_W-1:0] last_pixel_index_q;
  logic [COUNT_W-1:0] channel_index;
  logic [COUNT_W-1:0] last_channel_index_q;
  logic config_error;
  logic zero_length;
  logic transfer;
  logic last_channel;
  logic last_pixel;

  assign pixel_count = ADDR_W'(width) * ADDR_W'(height);
  assign config_error = (channels > COUNT_W'(MAX_C)) ||
                        (pixel_count > ADDR_W'(MAX_PIXELS));
  assign zero_length = (pixel_count == '0) || (channels == '0);
  assign transfer = (state == S_LOAD) && stream_valid;
  assign last_channel = channel_index == last_channel_index_q;
  assign last_pixel = pixel_index == last_pixel_index_q;

  assign stream_ready = (state == S_LOAD);
  assign write_enable = transfer;
  assign write_pixel = pixel_index;
  assign write_channel = channel_index;
  assign write_data = stream_data;
  assign busy = (state == S_LOAD);

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
            state <= (config_error || zero_length) ? S_DONE : S_LOAD;
          end
        end

        S_LOAD: begin
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
