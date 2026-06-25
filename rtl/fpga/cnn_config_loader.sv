`timescale 1ns/1ps

module cnn_config_loader #(
  parameter int NUM_INPUT_CHANNELS  = 3,
  parameter int NUM_OUTPUT_CHANNELS = 4,
  parameter int KERNEL_TAPS         = 9,
  parameter int DATA_WIDTH          = 8,
  parameter int WEIGHT_WIDTH        = 8,
  parameter int BIAS_WIDTH          = 32
)(
  input  logic clk,
  input  logic rst_n,
  input  logic clear,

  input  logic       cfg_valid,
  input  logic [15:0] cfg_width,
  input  logic [15:0] cfg_height,
  input  logic        cfg_kernel_mode,
  input  logic        cfg_relu_enable,
  input  logic        cfg_bias_enable,
  input  logic        cfg_quant_enable,
  input  logic [4:0]  cfg_quant_shift,

  input  logic        weight_valid,
  input  logic [7:0]  weight_index,
  input  logic signed [WEIGHT_WIDTH-1:0] weight_data,
  input  logic        weights_done,

  input  logic        bias_valid,
  input  logic [1:0]  bias_index,
  input  logic signed [BIAS_WIDTH-1:0] bias_data,
  input  logic        bias_done,

  output logic [15:0] image_width,
  output logic [15:0] image_height,
  output logic        kernel_mode,
  output logic        relu_enable,
  output logic        bias_enable,
  output logic        quant_enable,
  output logic [4:0]  quant_shift,

  output logic signed [WEIGHT_WIDTH-1:0] weights
    [NUM_OUTPUT_CHANNELS][NUM_INPUT_CHANNELS][KERNEL_TAPS],

  output logic signed [BIAS_WIDTH-1:0] bias
    [NUM_OUTPUT_CHANNELS],

  output logic config_loaded,
  output logic weights_loaded,
  output logic bias_loaded,

  output logic [31:0] cfg_write_count,
  output logic [31:0] weight_write_count,
  output logic [31:0] bias_write_count
);

  localparam int NUM_WEIGHTS = NUM_OUTPUT_CHANNELS * NUM_INPUT_CHANNELS * KERNEL_TAPS;

  int oc_idx;
  int ic_idx;
  int tap_idx;

  always_comb begin
    oc_idx  = weight_index / (NUM_INPUT_CHANNELS * KERNEL_TAPS);
    ic_idx  = (weight_index / KERNEL_TAPS) % NUM_INPUT_CHANNELS;
    tap_idx = weight_index % KERNEL_TAPS;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      image_width  <= 16'd0;
      image_height <= 16'd0;

      kernel_mode  <= 1'b1;
      relu_enable  <= 1'b0;
      bias_enable  <= 1'b0;
      quant_enable <= 1'b0;
      quant_shift  <= 5'd0;

      config_loaded  <= 1'b0;
      weights_loaded <= 1'b0;
      bias_loaded    <= 1'b0;

      cfg_write_count    <= 32'd0;
      weight_write_count <= 32'd0;
      bias_write_count   <= 32'd0;

      for (int oc = 0; oc < NUM_OUTPUT_CHANNELS; oc++) begin
        bias[oc] <= '0;

        for (int ic = 0; ic < NUM_INPUT_CHANNELS; ic++) begin
          for (int k = 0; k < KERNEL_TAPS; k++) begin
            weights[oc][ic][k] <= '0;
          end
        end
      end
    end else begin
      if (clear) begin
        image_width  <= 16'd0;
        image_height <= 16'd0;

        kernel_mode  <= 1'b1;
        relu_enable  <= 1'b0;
        bias_enable  <= 1'b0;
        quant_enable <= 1'b0;
        quant_shift  <= 5'd0;

        config_loaded  <= 1'b0;
        weights_loaded <= 1'b0;
        bias_loaded    <= 1'b0;

        cfg_write_count    <= 32'd0;
        weight_write_count <= 32'd0;
        bias_write_count   <= 32'd0;

        for (int oc = 0; oc < NUM_OUTPUT_CHANNELS; oc++) begin
          bias[oc] <= '0;

          for (int ic = 0; ic < NUM_INPUT_CHANNELS; ic++) begin
            for (int k = 0; k < KERNEL_TAPS; k++) begin
              weights[oc][ic][k] <= '0;
            end
          end
        end
      end else begin
        if (cfg_valid) begin
          image_width  <= cfg_width;
          image_height <= cfg_height;

          kernel_mode  <= cfg_kernel_mode;
          relu_enable  <= cfg_relu_enable;
          bias_enable  <= cfg_bias_enable;
          quant_enable <= cfg_quant_enable;
          quant_shift  <= cfg_quant_shift;

          config_loaded <= 1'b1;
          cfg_write_count <= cfg_write_count + 32'd1;
        end

        if (weight_valid) begin
          if (weight_index < NUM_WEIGHTS) begin
            weights[oc_idx][ic_idx][tap_idx] <= weight_data;
            weight_write_count <= weight_write_count + 32'd1;
          end
        end

        if (weights_done) begin
          weights_loaded <= 1'b1;
        end

        if (bias_valid) begin
          bias[bias_index] <= bias_data;
          bias_write_count <= bias_write_count + 32'd1;
        end

        if (bias_done) begin
          bias_loaded <= 1'b1;
        end
      end
    end
  end

endmodule
