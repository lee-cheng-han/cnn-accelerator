`timescale 1ns/1ps

module uart_cmd_decoder #(
  parameter int NUM_INPUT_CHANNELS  = 3,
  parameter int NUM_OUTPUT_CHANNELS = 4,
  parameter int KERNEL_TAPS         = 9
)(
  input  logic clk,
  input  logic rst_n,
  input  logic clear,

  input  logic [7:0] rx_data,
  input  logic       rx_valid,

  output logic       ping_valid,
  output logic       read_request_valid,

  output logic       cfg_valid,
  output logic [15:0] cfg_width,
  output logic [15:0] cfg_height,
  output logic        cfg_kernel_mode,
  output logic        cfg_relu_enable,
  output logic        cfg_bias_enable,
  output logic        cfg_quant_enable,
  output logic [4:0]  cfg_quant_shift,

  output logic        weight_valid,
  output logic [7:0]  weight_index,
  output logic signed [7:0] weight_data,
  output logic        weights_done,

  output logic        bias_valid,
  output logic [1:0]  bias_index,
  output logic signed [31:0] bias_data,
  output logic        bias_done,

  output logic        pixel_valid,
  output logic signed [7:0] pixel_data,

  output logic        protocol_error
);

  localparam int NUM_WEIGHTS = NUM_INPUT_CHANNELS * NUM_OUTPUT_CHANNELS * KERNEL_TAPS;
  localparam int NUM_BIAS    = NUM_OUTPUT_CHANNELS;

  typedef enum logic [3:0] {
    S_IDLE,

    S_CFG_W0,
    S_CFG_W1,
    S_CFG_H0,
    S_CFG_H1,
    S_CFG_MODE,
    S_CFG_FLAGS,
    S_CFG_SHIFT,

    S_WEIGHTS,

    S_BIAS_B0,
    S_BIAS_B1,
    S_BIAS_B2,
    S_BIAS_B3,

    S_IMAGE
  } state_t;

  state_t state;

  logic [7:0] weight_count;
  logic [1:0] bias_count;
  logic [1:0] bias_byte_count;
  logic signed [31:0] bias_shift;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;

      ping_valid         <= 1'b0;
      read_request_valid <= 1'b0;
      cfg_valid          <= 1'b0;
      weight_valid       <= 1'b0;
      weights_done       <= 1'b0;
      bias_valid         <= 1'b0;
      bias_done          <= 1'b0;
      pixel_valid        <= 1'b0;
      protocol_error     <= 1'b0;

      cfg_width        <= 16'd0;
      cfg_height       <= 16'd0;
      cfg_kernel_mode  <= 1'b1;
      cfg_relu_enable  <= 1'b0;
      cfg_bias_enable  <= 1'b0;
      cfg_quant_enable <= 1'b0;
      cfg_quant_shift  <= 5'd0;

      weight_index <= 8'd0;
      weight_data  <= 8'sd0;
      weight_count <= 8'd0;

      bias_index      <= 2'd0;
      bias_data       <= 32'sd0;
      bias_count      <= 2'd0;
      bias_byte_count <= 2'd0;
      bias_shift      <= 32'sd0;

      pixel_data <= 8'sd0;
    end else begin
      ping_valid         <= 1'b0;
      read_request_valid <= 1'b0;
      cfg_valid          <= 1'b0;
      weight_valid       <= 1'b0;
      weights_done       <= 1'b0;
      bias_valid         <= 1'b0;
      bias_done          <= 1'b0;
      pixel_valid        <= 1'b0;
      protocol_error     <= 1'b0;

      if (clear) begin
        state <= S_IDLE;
        weight_count <= 8'd0;
        bias_count <= 2'd0;
        bias_byte_count <= 2'd0;
        bias_shift <= 32'sd0;
      end else if (rx_valid) begin
        unique case (state)
          S_IDLE: begin
            unique case (rx_data)
              "P": begin
                ping_valid <= 1'b1;
              end

              "R": begin
                read_request_valid <= 1'b1;
              end

              "C": begin
                state <= S_CFG_W0;
              end

              "W": begin
                weight_count <= 8'd0;
                state <= S_WEIGHTS;
              end

              "B": begin
                bias_count <= 2'd0;
                bias_byte_count <= 2'd0;
                bias_shift <= 32'sd0;
                state <= S_BIAS_B0;
              end

              "I": begin
                state <= S_IMAGE;
              end

              default: begin
                protocol_error <= 1'b1;
              end
            endcase
          end

          S_CFG_W0: begin
            cfg_width[7:0] <= rx_data;
            state <= S_CFG_W1;
          end

          S_CFG_W1: begin
            cfg_width[15:8] <= rx_data;
            state <= S_CFG_H0;
          end

          S_CFG_H0: begin
            cfg_height[7:0] <= rx_data;
            state <= S_CFG_H1;
          end

          S_CFG_H1: begin
            cfg_height[15:8] <= rx_data;
            state <= S_CFG_MODE;
          end

          S_CFG_MODE: begin
            cfg_kernel_mode <= rx_data[0];
            state <= S_CFG_FLAGS;
          end

          S_CFG_FLAGS: begin
            cfg_relu_enable  <= rx_data[0];
            cfg_bias_enable  <= rx_data[1];
            cfg_quant_enable <= rx_data[2];
            state <= S_CFG_SHIFT;
          end

          S_CFG_SHIFT: begin
            cfg_quant_shift <= rx_data[4:0];
            cfg_valid <= 1'b1;
            state <= S_IDLE;
          end

          S_WEIGHTS: begin
            weight_index <= weight_count;
            weight_data  <= rx_data;
            weight_valid <= 1'b1;

            if (weight_count == NUM_WEIGHTS - 1) begin
              weights_done <= 1'b1;
              weight_count <= 8'd0;
              state <= S_IDLE;
            end else begin
              weight_count <= weight_count + 8'd1;
            end
          end

          S_BIAS_B0: begin
            bias_shift[7:0] <= rx_data;
            state <= S_BIAS_B1;
          end

          S_BIAS_B1: begin
            bias_shift[15:8] <= rx_data;
            state <= S_BIAS_B2;
          end

          S_BIAS_B2: begin
            bias_shift[23:16] <= rx_data;
            state <= S_BIAS_B3;
          end

          S_BIAS_B3: begin
            bias_shift[31:24] <= rx_data;

            bias_index <= bias_count;
            bias_data <= {rx_data, bias_shift[23:0]};
            bias_valid <= 1'b1;

            if (bias_count == NUM_BIAS - 1) begin
              bias_done <= 1'b1;
              bias_count <= 2'd0;
              state <= S_IDLE;
            end else begin
              bias_count <= bias_count + 2'd1;
              state <= S_BIAS_B0;
            end
          end

          S_IMAGE: begin
            if (rx_data == "R") begin
              read_request_valid <= 1'b1;
              state <= S_IDLE;
            end else begin
              pixel_data  <= rx_data;
              pixel_valid <= 1'b1;
            end
          end

          default: begin
            state <= S_IDLE;
            protocol_error <= 1'b1;
          end
        endcase
      end
    end
  end

endmodule
