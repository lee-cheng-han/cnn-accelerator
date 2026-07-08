`timescale 1ns/1ps

module weight_tensor_load_controller #(
  parameter int MAX_CIN  = 64,
  parameter int MAX_COUT = 64,
  parameter int DATA_W   = 8,
  parameter int COUNT_W  = 8
)(
  input  logic clk,
  input  logic rst_n,

  input  logic start,
  input  logic [COUNT_W-1:0] cout,
  input  logic [COUNT_W-1:0] cin,
  input  logic [1:0] kernel_size,

  input  logic stream_valid,
  output logic stream_ready,
  input  logic signed [DATA_W-1:0] stream_data,

  output logic write_enable,
  output logic [COUNT_W-1:0] write_out_channel,
  output logic [COUNT_W-1:0] write_in_channel,
  output logic [3:0] write_kernel_idx,
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

  logic [COUNT_W-1:0] out_channel;
  logic [COUNT_W-1:0] in_channel;
  logic [3:0] kernel_idx;
  logic [3:0] kernel_taps;
  logic config_error;
  logic zero_length;
  logic transfer;
  logic last_kernel;
  logic last_input;
  logic last_output;

  assign kernel_taps = (kernel_size == 2'd1) ? 4'd1 : 4'd9;
  assign config_error = ((kernel_size != 2'd1) && (kernel_size != 2'd3)) ||
                        (cin > COUNT_W'(MAX_CIN)) ||
                        (cout > COUNT_W'(MAX_COUT));
  assign zero_length = (cin == '0) || (cout == '0);
  assign transfer = (state == S_LOAD) && stream_valid;
  assign last_kernel = kernel_idx == (kernel_taps - 4'd1);
  assign last_input = in_channel == (cin - COUNT_W'(1));
  assign last_output = out_channel == (cout - COUNT_W'(1));

  assign stream_ready = (state == S_LOAD);
  assign write_enable = transfer;
  assign write_out_channel = out_channel;
  assign write_in_channel = in_channel;
  assign write_kernel_idx = kernel_idx;
  assign write_data = stream_data;
  assign busy = (state == S_LOAD);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      out_channel <= '0;
      in_channel <= '0;
      kernel_idx <= '0;
      done <= 1'b0;
      error <= 1'b0;
    end else begin
      done <= 1'b0;

      case (state)
        S_IDLE: begin
          if (start) begin
            out_channel <= '0;
            in_channel <= '0;
            kernel_idx <= '0;
            error <= config_error;
            state <= (config_error || zero_length) ? S_DONE : S_LOAD;
          end
        end

        S_LOAD: begin
          if (transfer) begin
            if (last_kernel && last_input && last_output) begin
              state <= S_DONE;
            end else if (last_kernel && last_input) begin
              kernel_idx <= '0;
              in_channel <= '0;
              out_channel <= out_channel + COUNT_W'(1);
            end else if (last_kernel) begin
              kernel_idx <= '0;
              in_channel <= in_channel + COUNT_W'(1);
            end else begin
              kernel_idx <= kernel_idx + 4'd1;
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
